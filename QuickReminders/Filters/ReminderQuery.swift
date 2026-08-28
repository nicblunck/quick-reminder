import EventKit
import Foundation

/// Reads reminders out of EventKit as `TaskItem` values.
///
/// The counterpart to `RemindersService`, which only ever writes. Kept separate
/// and free of any app-only dependency because the widget extension compiles
/// this file too and has no access to the app's `@Observable` services.
@MainActor
final class ReminderQuery {

    /// `nonisolated(unsafe)` because EventKit invokes a fetch's completion on
    /// its own private queue, so the store is necessarily reached from off the
    /// main actor while a fetch is in flight. EKEventStore tolerates that; the
    /// compiler cannot know it.
    nonisolated(unsafe) private let store = EKEventStore()

    init() {}

    // MARK: - Access

    nonisolated var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// Only ever called from the app. A widget extension cannot show a TCC
    /// prompt, so it must rely on the grant the app already obtained.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            NSLog("Quick Reminders: reminders access request failed — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reading

    /// Every reminder the filters might need, mapped to value types.
    ///
    /// Completed reminders are a second, separate fetch: they are unbounded and
    /// usually far more numerous than open ones, so paying for them only when a
    /// filter actually asks keeps the common case cheap.
    /// `nonisolated` end to end: the predicates are built and consumed in the
    /// same off-actor region as the fetch that uses them, which keeps the
    /// non-`Sendable` `NSPredicate` from having to cross an isolation boundary.
    nonisolated func fetchTasks(includeCompleted: Bool) async -> [TaskItem] {
        guard hasAccess else { return [] }

        var items = await fetch(store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        ))

        if includeCompleted {
            // Bounded deliberately: an all-time completed fetch on a long-lived
            // database can return tens of thousands of rows and stall the
            // widget's timeline past its budget.
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())
            items += await fetch(store.predicateForCompletedReminders(
                withCompletionDateStarting: cutoff, ending: nil, calendars: nil
            ))
        }

        return items
    }

    /// Deliberately `nonisolated`. Inside a `@MainActor` type this closure would
    /// inherit main-actor isolation, and EventKit calls it on a background queue
    /// — which trips libdispatch's queue assertion and takes the process down
    /// with "Block was expected to execute on queue [com.apple.main-thread]".
    nonisolated private func fetch(_ predicate: NSPredicate) async -> [TaskItem] {
        await withCheckedContinuation { continuation in
            // Mapping happens inside the callback: `EKReminder` is a reference
            // type tied to its store and is not `Sendable`, so only the flattened
            // values are allowed to cross back out.
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.taskItem))
            }
        }
    }

    // MARK: - Writing

    /// Ticking a reminder off from the widget.
    func setCompleted(_ completed: Bool, forTaskWithID id: String) throws {
        guard hasAccess else { throw RemindersError.noAccess }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    // MARK: - Mapping

    nonisolated private static func taskItem(_ reminder: EKReminder) -> TaskItem {
        let calendar = reminder.calendar
        return TaskItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            priority: normalisedPriority(reminder.priority),
            dueDate: date(from: reminder.dueDateComponents),
            // A day-only due date has no hour component, which is how EventKit
            // distinguishes "Friday" from "Friday at 17:45".
            hasTime: reminder.dueDateComponents?.hour != nil,
            startDate: date(from: reminder.startDateComponents),
            isRepeating: reminder.hasRecurrenceRules,
            listID: calendar?.calendarIdentifier ?? "",
            listTitle: calendar?.title ?? "",
            listColor: ListColor(cgColor: calendar?.cgColor),
            externalID: reminder.calendarItemExternalIdentifier
        )
    }

    nonisolated private static func date(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        if let direct = components.date { return direct }
        // Components written by other clients often carry no calendar, in which
        // case `.date` is nil and they have to be resolved explicitly.
        return Calendar.current.date(from: components)
    }

    /// EventKit's priority is a 0–9 scale where 1 is the most urgent and 0 means
    /// unset. Other clients write values our four-case enum has no raw value
    /// for, so anything off-scale is bucketed rather than dropped.
    nonisolated private static func normalisedPriority(_ raw: Int) -> ReminderPriority {
        switch raw {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }
}
