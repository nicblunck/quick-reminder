import Foundation
import Testing

/// Same frozen clock as the parser tests: every rule here is relative to "today",
/// so a wall-clock dependency would make these fail nightly.
private let zone = TimeZone(identifier: "America/Los_Angeles")!

private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    cal.locale = Locale(identifier: "en_US")
    return cal
}()

/// Monday 15 June 2026, 10:00.
private let now: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 15
    comps.hour = 10; comps.minute = 0
    comps.timeZone = zone
    return calendar.date(from: comps)!
}()

private func day(_ offset: Int, hour: Int = 12) -> Date {
    let start = calendar.startOfDay(for: now)
    let shifted = calendar.date(byAdding: .day, value: offset, to: start)!
    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted)!
}

private func task(
    _ id: String,
    _ title: String,
    due: Date? = nil,
    hasTime: Bool = true,
    list: String = "work",
    completed: Bool = false,
    priority: ReminderPriority = .none,
    repeating: Bool = false,
    notes: String? = nil
) -> TaskItem {
    TaskItem(
        id: id, title: title, notes: notes, isCompleted: completed, priority: priority,
        dueDate: due, hasTime: hasTime, startDate: nil, isRepeating: repeating,
        listID: list, listTitle: list.capitalized, listColor: nil
    )
}

private func run(_ filter: TaskFilter, _ items: [TaskItem]) -> [String] {
    FilterEvaluator.evaluate(filter, against: items, now: now, calendar: calendar).map(\.id)
}

// MARK: - The three filters from the brief

/// Fixture spanning every bucket the three shipped filters divide time into.
private let corpus: [TaskItem] = [
    task("overdue-work", "Overdue work", due: day(-2), list: "work"),
    task("today-work", "Due today", due: day(0), list: "work"),
    task("today-home", "Due today, personal", due: day(0), list: "home"),
    task("tomorrow-work", "Due tomorrow", due: day(1), list: "work"),
    task("day7-work", "Due in a week", due: day(7), list: "work"),
    task("day8-work", "Due in eight days", due: day(8), list: "work"),
    task("far-home", "Due next month", due: day(30), list: "home"),
    task("undated-work", "No deadline", due: nil, list: "work"),
    task("undated-home", "No deadline, personal", due: nil, list: "home"),
    task("done-today", "Already done", due: day(0), list: "work", completed: true),
]

@Test("Work Today matches today and anything already overdue, in work lists only")
func workTodayFilter() {
    let filter = TaskFilter(
        name: "Work Today",
        root: .all([
            .rule(.dueDate, .onOrBefore, .days(0)),
            .rule(.list, .isAnyOf, .lists(["work"])),
        ])
    )
    #expect(run(filter, corpus) == ["overdue-work", "today-work"])
}

@Test("Work This Week excludes today and stops at day seven")
func workThisWeekFilter() {
    let filter = TaskFilter(
        name: "Work This Week",
        root: .all([
            .rule(.dueDate, .onOrAfter, .days(1)),
            .rule(.dueDate, .onOrBefore, .days(7)),
            .rule(.list, .isAnyOf, .lists(["work"])),
        ])
    )
    #expect(run(filter, corpus) == ["tomorrow-work", "day7-work"])
}

@Test("Later takes everything beyond the week *or* with no deadline at all")
func laterFilter() {
    let filter = TaskFilter(
        name: "Later",
        root: .any([
            .rule(.dueDate, .onOrAfter, .days(8)),
            .rule(.dueDate, .doesNotExist),
        ])
    )
    // Dated ones sort first and undated ones fall to the end, alphabetically.
    #expect(run(filter, corpus) == ["day8-work", "far-home", "No deadline", "No deadline, personal"]
        .map { id in corpus.first { $0.id == id || $0.title == id }!.id })
}

@Test("The three filters together partition every open reminder exactly once")
func filtersPartitionTheCorpus() {
    let today = TaskFilter(root: .all([.rule(.dueDate, .onOrBefore, .days(0))]))
    let week = TaskFilter(root: .all([
        .rule(.dueDate, .onOrAfter, .days(1)), .rule(.dueDate, .onOrBefore, .days(7)),
    ]))
    let later = TaskFilter(root: .any([
        .rule(.dueDate, .onOrAfter, .days(8)), .rule(.dueDate, .doesNotExist),
    ]))

    let covered = run(today, corpus) + run(week, corpus) + run(later, corpus)
    let open = corpus.filter { !$0.isCompleted }.map(\.id)

    #expect(Set(covered) == Set(open))
    #expect(covered.count == open.count, "a reminder landed in more than one bucket")
}

// MARK: - Tree semantics

@Test("Completed reminders are hidden unless a rule asks for them")
func completionIsOptedInto() {
    let open = TaskFilter(root: .all([.rule(.dueDate, .onDay, .days(0))]))
    #expect(run(open, corpus) == ["today-work", "today-home"])

    let done = TaskFilter(root: .all([
        .rule(.dueDate, .onDay, .days(0)),
        .rule(.completion, .isTrue),
    ]))
    #expect(run(done, corpus) == ["done-today"])
}

@Test("An empty group matches everything rather than nothing")
func emptyGroupIsNeutral() {
    #expect(run(TaskFilter(), corpus).count == corpus.filter { !$0.isCompleted }.count)
}

@Test("An empty list selection constrains nothing")
func emptyListSelectionIsUnconstrained() {
    let filter = TaskFilter(root: .all([
        .rule(.dueDate, .onDay, .days(0)),
        .rule(.list, .isAnyOf, .lists([])),
    ]))
    #expect(run(filter, corpus) == ["today-work", "today-home"])
}

@Test("none inverts the whole group")
func noneCombinator() {
    let filter = TaskFilter(root: FilterGroup(combinator: .none, children: [
        .rule(.list, .isAnyOf, .lists(["work"])),
    ]))
    #expect(run(filter, corpus) == ["today-home", "far-home", "undated-home"])
}

@Test("Nested groups mix and with or")
func nestedGroups() {
    // Work list AND (overdue OR high priority)
    let items = corpus + [task("urgent", "Urgent", due: day(20), list: "work", priority: .high)]
    let filter = TaskFilter(root: .all([
        .rule(.list, .isAnyOf, .lists(["work"])),
        .group(.any([
            .rule(.dueDate, .isOverdue),
            .rule(.priority, .isAtLeast, .priority(.high)),
        ])),
    ]))
    #expect(run(filter, items) == ["overdue-work", "urgent"])
}

// MARK: - Individual rules

@Test("isAtLeast reads on urgency, not on EventKit's inverted raw values")
func priorityOrdering() {
    let items = [
        task("none", "None", priority: .none),
        task("low", "Low", priority: .low),
        task("med", "Medium", priority: .medium),
        task("high", "High", priority: .high),
    ]
    let atLeastMedium = TaskFilter(root: .all([.rule(.priority, .isAtLeast, .priority(.medium))]))
    #expect(Set(run(atLeastMedium, items)) == ["med", "high"])

    let atMostLow = TaskFilter(root: .all([.rule(.priority, .isAtMost, .priority(.low))]))
    #expect(Set(run(atMostLow, items)) == ["none", "low"])
}

@Test("Overdue means the moment has passed, not merely that the day has")
func overdueUsesTheClock() {
    let items = [
        task("earlier", "Earlier today", due: day(0, hour: 9)),
        task("later", "Later today", due: day(0, hour: 17)),
    ]
    let filter = TaskFilter(root: .all([.rule(.dueDate, .isOverdue)]))
    #expect(run(filter, items) == ["earlier"])
}

@Test("Title matching ignores case and accents")
func titleMatching() {
    let items = [task("a", "Café résumé"), task("b", "Something else")]
    let filter = TaskFilter(root: .all([.rule(.title, .contains, .text("cafe"))]))
    #expect(run(filter, items) == ["a"])
}

@Test("Undated reminders sort last in both directions")
func undatedSortsLast() {
    let items = [
        task("undated", "Undated", due: nil),
        task("soon", "Soon", due: day(1)),
        task("late", "Late", due: day(9)),
    ]
    #expect(run(TaskFilter(sort: .dueDateAscending), items) == ["soon", "late", "undated"])
    #expect(run(TaskFilter(sort: .dueDateDescending), items) == ["late", "soon", "undated"])
}

@Test("maxCount trims after sorting, not before")
func maxCountAppliesToSortedResults() {
    let items = [
        task("c", "C", due: day(3)), task("a", "A", due: day(1)), task("b", "B", due: day(2)),
    ]
    #expect(run(TaskFilter(sort: .dueDateAscending, maxCount: 2), items) == ["a", "b"])
}

@Test("A day-only reminder is not overdue during its own day")
func dayOnlyRemindersAreNotOverdueUntilTheDayEnds() {
    // EventKit gives a day-only due date no hour component, so it resolves to
    // midnight — the naive comparison would call it overdue from 00:01.
    let items = [
        task("today-dayonly", "Today, no time", due: day(0, hour: 0), hasTime: false),
        task("yesterday-dayonly", "Yesterday, no time", due: day(-1, hour: 0), hasTime: false),
        task("earlier-timed", "Earlier today, timed", due: day(0, hour: 9), hasTime: true),
    ]
    let filter = TaskFilter(root: .all([.rule(.dueDate, .isOverdue)]))
    #expect(run(filter, items) == ["yesterday-dayonly", "earlier-timed"])
}
