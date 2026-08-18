import SwiftUI

/// The time counterpart to `DatePopoverView`: the three shortcuts, then hour and
/// minute as two independently scrollable columns.
///
/// macOS has no wheel-style `DatePicker` — that style is iOS only — so the split
/// is built from two scroll views. The toolbar keeps its − / + steppers for
/// nudging; this is for jumping.
struct TimePopoverView: View {
    @Binding var selection: TimeOfDay?
    var onClear: () -> Void
    var onClose: () -> Void

    /// Minute granularity. The steppers cover finer nudging.
    private static let minuteStep = 5
    private static let fallback = TimeOfDay(hour: 9, minute: 0)

    private var current: TimeOfDay { selection ?? Self.fallback }

    var body: some View {
        VStack(spacing: 12) {
            shortcuts
            Divider()
            columns
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 250)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        HStack(spacing: 6) {
            ForEach(TimeOfDay.presets, id: \.label) { preset in
                Button {
                    selection = preset
                    // A shortcut is a complete time, so it commits and closes.
                    onClose()
                } label: {
                    Text(preset.label)
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.quaternary.opacity(0.6)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Columns

    private var columns: some View {
        HStack(spacing: 10) {
            column(
                title: "Hour",
                values: Array(0..<24),
                selected: current.hour
            ) { selection = TimeOfDay(hour: $0, minute: current.minute) }

            column(
                title: "Minute",
                values: Array(stride(from: 0, to: 60, by: Self.minuteStep)),
                selected: current.minute
            ) { selection = TimeOfDay(hour: current.hour, minute: $0) }
        }
    }

    private func column(
        title: String,
        values: [Int],
        selected: Int,
        onPick: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    // Not Lazy: `scrollTo` cannot reach a row that has not been
                    // created, and two dozen rows cost nothing.
                    VStack(spacing: 1) {
                        ForEach(values, id: \.self) { value in
                            valueRow(value, isSelected: value == selected) { onPick(value) }
                                .id(value)
                        }
                    }
                    .padding(.horizontal, 3)
                }
                .frame(height: 176)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .task {
                    // Open on the current value rather than at the top.
                    try? await Task.sleep(for: .milliseconds(20))
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    private func valueRow(_ value: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(String(format: "%02d", value))
                .font(.body.monospacedDigit())
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if selection != nil {
                Button(action: onClear) {
                    Text("Remove").font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            // The columns are picked one at a time, so this cannot close on
            // selection the way the shortcuts and the calendar do.
            Button("Done") { onClose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
    }

    private struct RowButtonStyle: ButtonStyle {
        @State private var hovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .opacity(hovering && !configuration.isPressed ? 1 : 0)
                }
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}
