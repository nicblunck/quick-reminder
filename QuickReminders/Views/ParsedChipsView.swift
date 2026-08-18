import SwiftUI

/// Date, time and priority as three independent chips, so a misparse is visible
/// before saving and each part can be dropped on its own.
struct ParsedChipsView: View {
    let day: Date?
    let time: TimeOfDay?
    let priority: ReminderPriority
    var onRemoveDay: () -> Void
    var onRemoveTime: () -> Void
    var onRemovePriority: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let day {
                Chip(tint: .blue, onRemove: onRemoveDay) {
                    Image(systemName: "calendar").imageScale(.small)
                    Text(Self.formatDay(day))
                }
                .transition(Self.chipTransition)
            }
            if let time {
                Chip(tint: .red, onRemove: onRemoveTime) {
                    Image(systemName: "clock").imageScale(.small)
                    Text(time.label).contentTransition(.numericText())
                }
                .transition(Self.chipTransition)
            }
            if priority != .none {
                Chip(tint: .orange, onRemove: onRemovePriority) {
                    PriorityMarksView(priority: priority)
                }
                .transition(Self.chipTransition)
            }
        }
    }

    /// Chips grow out of, and shrink back into, their leading edge rather than
    /// their centre, so neighbours are not nudged around as one is removed.
    private static let chipTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.7, anchor: .leading).combined(with: .opacity),
        removal: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
    )

    static func formatDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)
        ).day ?? 0
        if (0...6).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private struct Chip<Label: View>: View {
        let tint: Color
        var onRemove: () -> Void
        @ViewBuilder var label: Label

        var body: some View {
            HStack(spacing: 4) {
                label
                    .font(.callout.weight(.medium))
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .opacity(0.65)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
        }
    }
}
