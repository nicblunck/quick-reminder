import Foundation

/// What `ReminderParser` extracted from the raw input string.
struct ParseResult: Equatable, Sendable {
    /// The input with every recognised token removed and whitespace collapsed.
    var cleanedTitle: String = ""
    var dueDate: Date?
    /// True only when the user actually specified a clock time.
    var hasTime: Bool = false
    var priority: ReminderPriority = .none
    /// The literal text the date came from, for the chip label and for "pin as literal".
    var dueSourceText: String?
    var prioritySourceText: String?

    static let empty = ParseResult()
}
