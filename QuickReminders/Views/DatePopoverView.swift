import SwiftUI

/// Everything about the due date in one place: the common shortcuts and the
/// full calendar together, rather than a menu whose last item opens a second
/// popover to reach the grid.
struct DatePopoverView: View {
    @Binding var selection: Date
    var hasDate: Bool
    var onClear: () -> Void
    var onClose: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            shortcuts
            Divider()
            CalendarGridView(selection: $selection)
            if hasDate {
                Divider()
                Button(role: .destructive, action: onClear) {
                    Text("Remove Date").frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
        }
        .padding(16)
        .onChange(of: selection) { _, _ in
            // Any pick is decisive; nothing here needs a confirm step.
            onClose()
        }
    }

    private var shortcuts: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                shortcut("Today", days: 0)
                shortcut("Tomorrow", days: 1)
            }
            GridRow {
                shortcut("Next Week", days: 7)
                shortcut("Next Month", months: 1)
            }
        }
    }

    private func shortcut(_ title: String, days: Int = 0, months: Int = 0) -> some View {
        Button {
            let today = calendar.startOfDay(for: Date())
            let shifted = calendar.date(byAdding: .month, value: months, to: today) ?? today
            selection = calendar.date(byAdding: .day, value: days, to: shifted) ?? shifted
        } label: {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
