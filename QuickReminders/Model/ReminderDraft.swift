import Foundation

/// Priority levels, using the raw values EventKit expects for `EKReminder.priority`.
/// Kept as our own type so the model and parser layers stay free of EventKit.
enum ReminderPriority: Int, CaseIterable, Sendable, Codable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    var label: String {
        switch self {
        case .none: "None"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    /// `!` = low, `!!` = medium, `!!!` = high.
    var bangs: String { String(repeating: "!", count: bangCount) }

    var bangCount: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }


    /// none → ! → !! → !!! → none, for the click-to-cycle toolbar button.
    var cyclingNext: ReminderPriority {
        switch self {
        case .none: .low
        case .low: .medium
        case .medium: .high
        case .high: .none
        }
    }

    init(bangCount: Int) {
        switch bangCount {
        case 1: self = .low
        case 2: self = .medium
        case 3...: self = .high
        default: self = .none
        }
    }
}

/// Everything the user can capture in one pass. This is the unit handed to a
/// `ReminderWriter`; adding tags/flag/images later means adding fields here plus
/// a writer that knows how to persist them.
struct ReminderDraft: Equatable, Sendable {
    var title: String = ""
    var notes: String = ""
    /// `EKCalendar.calendarIdentifier` of the destination list.
    var listID: String?
    var dueDate: Date?
    /// False when the user gave a day but no clock time, so the writer can
    /// substitute the configured default reminder time.
    var hasTime: Bool = false
    var priority: ReminderPriority = .none

    var isSubmittable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}
