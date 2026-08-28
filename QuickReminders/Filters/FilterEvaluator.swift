import Foundation

/// Runs a `TaskFilter` over a list of `TaskItem`s.
///
/// Pure and free of EventKit, `@MainActor` and `UserDefaults`, so the same code
/// backs the app's live preview, the widget timeline and the unit tests. Every
/// relative date is resolved against an injected `now`, which is what makes
/// "due today" testable without waiting for midnight.
enum FilterEvaluator {

    // MARK: - Entry point

    static func evaluate(
        _ filter: TaskFilter,
        against items: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let honoursCompletion = filter.includeCompleted || mentionsCompletion(filter.root)

        var matched = items.filter { item in
            if !honoursCompletion && item.isCompleted { return false }
            return matches(filter.root, item, now: now, calendar: calendar)
        }

        matched = sort(matched, by: filter.sort, now: now)
        if filter.maxCount > 0 { matched = Array(matched.prefix(filter.maxCount)) }
        return matched
    }

    /// A tree that tests completion explicitly opts out of the blanket
    /// "hide completed" rule, so `completion is yes` is not silently impossible.
    private static func mentionsCompletion(_ group: FilterGroup) -> Bool {
        group.children.contains { node in
            switch node {
            case .rule(let rule): rule.field == .completion
            case .group(let child): mentionsCompletion(child)
            }
        }
    }

    // MARK: - Tree

    static func matches(
        _ group: FilterGroup, _ item: TaskItem, now: Date, calendar: Calendar
    ) -> Bool {
        // An empty group is neutral rather than false: a filter being built in
        // the editor should show everything, not nothing.
        guard !group.children.isEmpty else { return true }

        let results = group.children.lazy.map { node -> Bool in
            switch node {
            case .rule(let rule): matches(rule, item, now: now, calendar: calendar)
            case .group(let child): matches(child, item, now: now, calendar: calendar)
            }
        }

        switch group.combinator {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains { $0 }
        case .none: return !results.contains { $0 }
        }
    }

    // MARK: - Rules

    static func matches(
        _ rule: FilterRule, _ item: TaskItem, now: Date, calendar: Calendar
    ) -> Bool {
        switch rule.field {
        case .dueDate:
            return matchesDate(item.dueDate, hasTime: item.hasTime, rule, now: now, calendar: calendar)
        case .startDate:
            let hasTime = item.startDate.map { $0 != calendar.startOfDay(for: $0) } ?? false
            return matchesDate(item.startDate, hasTime: hasTime, rule, now: now, calendar: calendar)
        case .list:
            return matchesList(item, rule)
        case .priority:
            return matchesPriority(item, rule)
        case .title:
            return matchesText(item.title, rule)
        case .notes:
            return matchesText(item.notes ?? "", rule)
        case .completion:
            return rule.comparator == .isTrue ? item.isCompleted : !item.isCompleted
        case .repeating:
            return rule.comparator == .isTrue ? item.isRepeating : !item.isRepeating
        }
    }

    private static func matchesDate(
        _ date: Date?, hasTime: Bool, _ rule: FilterRule, now: Date, calendar: Calendar
    ) -> Bool {
        switch rule.comparator {
        case .exists: return date != nil
        case .doesNotExist: return date == nil
        case .isOverdue:
            guard let date else { return false }
            // A day-only reminder is not overdue until its day is over. Its
            // components carry no hour, so it resolves to midnight and would
            // otherwise read as overdue for the whole of its own day.
            guard hasTime else { return date < calendar.startOfDay(for: now) }
            return date < now
        case .hasClockTime:
            return date != nil && hasTime
        case .onDay, .onOrAfter, .onOrBefore:
            guard let date, let offset = rule.value.days else { return false }
            let today = calendar.startOfDay(for: now)
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { return false }

            switch rule.comparator {
            case .onDay: return date >= dayStart && date < dayEnd
            case .onOrAfter: return date >= dayStart
            // "on or before day N" includes everything up to that day's end.
            case .onOrBefore: return date < dayEnd
            default: return false
            }
        default:
            return false
        }
    }

    private static func matchesList(_ item: TaskItem, _ rule: FilterRule) -> Bool {
        guard let ids = rule.value.lists else { return false }
        // An unset list rule constrains nothing. Seeded filters ship this way
        // until the user picks their work lists, and matching everything is a
        // far better first impression than matching nothing.
        guard !ids.isEmpty else { return true }
        let isMember = ids.contains(item.listID)
        return rule.comparator == .isAnyOf ? isMember : !isMember
    }

    private static func matchesPriority(_ item: TaskItem, _ rule: FilterRule) -> Bool {
        guard let target = rule.value.priority else { return false }
        // EventKit stores 1 as the *highest* priority and 9 as the lowest, with
        // 0 meaning unset. Comparing on that scale directly reads backwards, so
        // rank on an ascending urgency scale instead.
        let rank = urgency(item.priority)
        let targetRank = urgency(target)
        switch rule.comparator {
        case .equals: return rank == targetRank
        case .isAtLeast: return rank >= targetRank
        case .isAtMost: return rank <= targetRank
        default: return false
        }
    }

    private static func urgency(_ priority: ReminderPriority) -> Int {
        switch priority {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    private static func matchesText(_ subject: String, _ rule: FilterRule) -> Bool {
        switch rule.comparator {
        case .exists: return !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .doesNotExist: return subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .contains, .doesNotContain, .beginsWith:
            guard let needle = rule.value.text, !needle.isEmpty else { return true }
            let found: Bool = switch rule.comparator {
            case .beginsWith: subject.lowercased().hasPrefix(needle.lowercased())
            default: subject.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            return rule.comparator == .doesNotContain ? !found : found
        default:
            return false
        }
    }

    // MARK: - Sorting

    private static func sort(_ items: [TaskItem], by order: FilterSort, now: Date) -> [TaskItem] {
        switch order {
        case .manual:
            return items
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .priorityFirst:
            return items.sorted { a, b in
                let (ua, ub) = (urgency(a.priority), urgency(b.priority))
                if ua != ub { return ua > ub }
                return earlier(a, b)
            }
        case .dueDateAscending:
            return items.sorted(by: earlier)
        case .dueDateDescending:
            return items.sorted { later($0, $1) }
        case .listThenDueDate:
            return items.sorted { a, b in
                if a.listTitle != b.listTitle {
                    return a.listTitle.localizedStandardCompare(b.listTitle) == .orderedAscending
                }
                return earlier(a, b)
            }
        }
    }

    /// Undated reminders sort last in both directions — they are the tail of a
    /// list, never the head of it.
    private static func earlier(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x == y ? tieBreak(a, b) : x < y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return tieBreak(a, b)
        }
    }

    private static func later(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x == y ? tieBreak(a, b) : x > y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return tieBreak(a, b)
        }
    }

    private static func tieBreak(_ a: TaskItem, _ b: TaskItem) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
