import Foundation

/// One reminder, flattened out of EventKit into a `Sendable` value.
///
/// Everything a filter can test and everything a widget row can draw lives here,
/// so neither the evaluator nor the widget views ever hold an `EKReminder` —
/// which is a reference type, not `Sendable`, and invalid once its store dies.
struct TaskItem: Identifiable, Hashable, Sendable, Codable {
    /// `EKReminder.calendarItemIdentifier`. Stable across launches, and what the
    /// complete-from-widget intent looks the reminder back up by.
    let id: String
    var title: String
    var notes: String?
    var isCompleted: Bool
    var priority: ReminderPriority

    /// Nil when the reminder is undated. `hasTime` is false for a day-only due
    /// date, which is the difference between "Friday" and "Friday, 17:45".
    var dueDate: Date?
    var hasTime: Bool
    /// Reminders lets a task start before it is due; a "scheduled" task has one
    /// or the other.
    var startDate: Date?
    var isRepeating: Bool

    var listID: String
    var listTitle: String
    var listColor: ListColor?

    /// `calendarItemExternalIdentifier`, which is what Reminders' own
    /// `x-apple-reminderkit://` links are keyed on. Separate from `id`, which is
    /// the local identifier used to look the reminder back up for writing.
    var externalID: String?

    /// Opens this reminder in Reminders.app, or just the app itself when the
    /// identifier is missing.
    var remindersURL: URL { Self.remindersURL(externalID: externalID) }

    static func remindersURL(externalID: String?) -> URL {
        guard let externalID, !externalID.isEmpty,
              let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(externalID)")
        else { return URL(string: "x-apple-reminderkit://")! }
        return url
    }

    /// What a widget row links to. A widget's link is delivered to its *own*
    /// app rather than opened system-wide, so it has to travel through our own
    /// scheme; `AppDelegate` turns it back into `remindersURL` and opens that.
    var widgetLinkURL: URL {
        guard let externalID, !externalID.isEmpty,
              var components = URLComponents(string: "quickreminders://reminder")
        else { return URL(string: "quickreminders://reminders")! }
        components.queryItems = [URLQueryItem(name: "id", value: externalID)]
        return components.url ?? URL(string: "quickreminders://reminders")!
    }

    var isScheduled: Bool { dueDate != nil || startDate != nil }
}
