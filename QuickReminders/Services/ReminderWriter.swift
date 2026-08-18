import CoreGraphics
import Foundation

/// The seam between "a captured draft" and "a persisted reminder".
///
/// Today there is exactly one conformance, `RemindersService` (EventKit). Tags,
/// flag and image attachments have no EventKit API, so adding them later means
/// writing a second conformance that routes the draft through a Shortcut —
/// nothing above this protocol has to change.
@MainActor
protocol ReminderWriter {
    func save(_ draft: ReminderDraft) throws
}

/// A list's colour, flattened to sRGB components so the type stays `Sendable`
/// and `Hashable` — `CGColor` is neither.
struct ListColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(cgColor: CGColor?) {
        guard let cgColor,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else { return nil }
        red = Double(components[0])
        green = Double(components[1])
        blue = Double(components[2])
    }
}

struct ReminderList: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let color: ListColor?
}

enum RemindersError: LocalizedError {
    case noAccess
    case noList
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .noAccess:
            "Quick Reminders doesn't have access to your reminders."
        case .noList:
            "No reminder list is available to save into."
        case .emptyTitle:
            "A reminder needs a title."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAccess:
            "Enable it in System Settings ▸ Privacy & Security ▸ Reminders."
        default:
            nil
        }
    }
}
