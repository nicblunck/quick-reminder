import Foundation

/// A clock time with no date attached — what the time chip represents.
struct TimeOfDay: Equatable, Sendable {
    var hour: Int
    var minute: Int
    /// True for a bare "at 5", which could mean 05:00 or 17:00.
    var isAmbiguous: Bool = false

    /// The three times offered by the clock dropdown.
    static let presets = [
        TimeOfDay(hour: 9, minute: 0),
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
    ]

    init(hour: Int, minute: Int, isAmbiguous: Bool = false) {
        self.hour = hour
        self.minute = minute
        self.isAmbiguous = isAmbiguous
    }

    init(from date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// Rendered with the system's short time style, so it follows the user's
    /// locale and their 24-Hour Time preference instead of assuming a format.
    var label: String {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var minutesSinceMidnight: Int { hour * 60 + minute }

    /// Steps the time, clamping within the same day rather than wrapping around
    /// midnight — stepping past 23:59 should stop, not silently jump to tomorrow.
    func stepped(byMinutes delta: Int) -> TimeOfDay {
        let total = min(max(minutesSinceMidnight + delta, 0), 23 * 60 + 59)
        return TimeOfDay(hour: total / 60, minute: total % 60)
    }

    func applied(to day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

}
