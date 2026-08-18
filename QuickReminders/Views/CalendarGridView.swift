import SwiftUI

/// A month grid sized for a floating panel.
///
/// `NSDatePicker` stops growing at roughly font 18 — larger fonts render
/// identically — so a calendar at this scale cannot be had from the system
/// control. Everything locale-dependent still comes from `Calendar` and
/// `FormatStyle`: first day of the week, weekday names, month names.
struct CalendarGridView: View {
    @Binding var selection: Date
    var calendar: Calendar = .current

    @State private var visibleMonth = Date()

    private let cell: CGFloat = 38
    private let columnSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayHeader
            grid
        }
        .task { visibleMonth = selection }
        .onChange(of: selection) { _, new in
            // Follow a selection made elsewhere (typing "next month", say).
            if !calendar.isDate(new, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = new
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
            Spacer(minLength: 12)
            stepMonthButton(symbol: "chevron.left", months: -1)
            stepMonthButton(symbol: "chevron.right", months: 1)
        }
    }

    private func stepMonthButton(symbol: String, months: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                visibleMonth = calendar.date(byAdding: .month, value: months, to: visibleMonth)
                    ?? visibleMonth
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        HStack(spacing: columnSpacing) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: cell)
            }
        }
    }

    /// `shortWeekdaySymbols` always starts on Sunday, so rotate it to wherever
    /// the user's calendar actually begins.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return (Array(symbols[shift...]) + Array(symbols[..<shift]))
            .map { $0.uppercased() }
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: columnSpacing) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: columnSpacing) {
                    ForEach(0..<7, id: \.self) { column in
                        dayCell(gridDates[row * 7 + column])
                    }
                }
            }
        }
    }

    /// Always six rows, so the popover keeps one height as months change.
    private var gridDates: [Date] {
        let components = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let startOfMonth = calendar.date(from: components) else { return [] }
        let weekdayOfFirst = calendar.component(.weekday, from: startOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: startOfMonth) else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)

        return Button {
            selection = date
        } label: {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 15, weight: isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, inMonth: inMonth))
                .frame(width: cell, height: cell)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().fill(Color.accentColor.opacity(0.12))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(DayButtonStyle())
    }

    private func dayColor(isSelected: Bool, isToday: Bool, inMonth: Bool) -> some ShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        if isToday { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }

    /// Hover and press feedback, which `.plain` gives up entirely.
    private struct DayButtonStyle: ButtonStyle {
        @State private var hovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    Circle()
                        .fill(.quaternary)
                        .opacity(hovering && !configuration.isPressed ? 1 : 0)
                }
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}
