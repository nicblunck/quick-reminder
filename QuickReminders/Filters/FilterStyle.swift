import SwiftUI

extension FilterTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .indigo: .indigo
        case .teal: .teal
        case .mint: .mint
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .brown: .brown
        case .graphite: .secondary
        }
    }
}

extension ListColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// How a due date reads on a widget row.
///
/// Near dates are named rather than numbered — "Today, 17:45" tells you more at
/// a glance than "27/8, 17:45" — and the year is only spelled out when it is not
/// the current one.
enum DueDateFormat {

    static func label(for item: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let due = item.dueDate else { return nil }

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

        let day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        // Inside the coming week a weekday name is unambiguous; beyond it,
        // "Tuesday" could mean either of two Tuesdays.
        case 2...6: day = due.formatted(.dateTime.weekday(.wide))
        default:
            day = calendar.isDate(due, equalTo: now, toGranularity: .year)
                ? due.formatted(.dateTime.day().month(.abbreviated))
                : due.formatted(.dateTime.day().month(.abbreviated).year())
        }

        guard item.hasTime else { return day }
        return "\(day), \(due.formatted(.dateTime.hour().minute()))"
    }

    /// Overdue rows are the only ones that earn a colour of their own.
    ///
    /// Day-only reminders stay black until their day is actually over — they
    /// resolve to midnight, so comparing them against the clock would paint
    /// every one of today's reminders red from 00:01.
    static func isOverdue(_ item: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due = item.dueDate, !item.isCompleted else { return false }
        guard item.hasTime else { return due < calendar.startOfDay(for: now) }
        return due < now
    }
}
