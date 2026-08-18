import SwiftUI

/// The `!` / `!!` / `!!!` indicator.
///
/// Each mark rises into place as the priority goes up and drops away as it comes
/// down — the directional feel of Apple's numeric text transition, built out
/// explicitly because `.numericText()` only rolls digits, not punctuation.
struct PriorityMarksView: View {
    let priority: ReminderPriority
    /// Draw a single mark even at `.none`, so the toolbar button has something
    /// to grey out rather than disappearing.
    var showsPlaceholder = false

    private var count: Int {
        showsPlaceholder ? max(priority.bangCount, 1) : priority.bangCount
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<count, id: \.self) { _ in
                Text("!")
                    // An offset rather than `.move(edge:)`: it travels a short,
                    // fixed distance and fades on the way, so nothing needs
                    // clipping and the marks never collide with their neighbours.
                    .transition(
                        .offset(y: 9).combined(with: .opacity)
                    )
            }
        }
        .animation(.snappy(duration: 0.22, extraBounce: 0.1), value: count)
    }
}
