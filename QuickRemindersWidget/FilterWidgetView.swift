import AppIntents
import SwiftUI
import WidgetKit

struct FilterWidgetView: View {
    var entry: FilterEntry
    /// Set only by the snapshot tool. `widgetFamily` is read-only in the
    /// environment, so a view rendered outside a widget host has no other way to
    /// be told which size it is standing in for.
    var familyOverride: WidgetFamily?

    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var tint: Color { entry.filter?.tint.color ?? .blue }

    /// How many rows fit before the widget starts clipping.
    private var rowLimit: Int {
        switch family {
        case .systemSmall, .systemMedium: 3
        // One fewer than before: a wrapped title is twice as tall, and a row
        // sliced in half at the bottom edge looks worse than one row less.
        default: 7
        }
    }

    /// Reminders' own rows breathe: a 21pt circle and a wide gap, not a dense
    /// list. Matching that is most of what makes this look native.
    private var rowSpacing: CGFloat { 13 }

    private var showsTrailingDetail: Bool { family != .systemSmall }

    /// The widget's own margins. `contentMarginsDisabled()` turns off the
    /// system's, which is only worth doing if we then supply our own — without
    /// this the header sits hard against the rounded corner.
    private var contentPadding: EdgeInsets {
        switch family {
        case .systemSmall: EdgeInsets(top: 15, leading: 15, bottom: 13, trailing: 15)
        default: EdgeInsets(top: 17, leading: 17, bottom: 14, trailing: 17)
        }
    }

    var body: some View {
        // Top-aligned so that when wrapped titles make the rows taller than the
        // card, what falls off the end is the last row — never the header. A
        // centred stack clips both edges and takes the filter's name with it.
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 11) {
                header
                if emptyState == nil {
                    // No trailing Spacer: it competes with the rows for height,
                    // and ViewThatFits then measures against what is left over
                    // and steps down further than it needs to. The outer frame
                    // already pins all of this to the top.
                    rows
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Laid over the whole card rather than placed under the header, so
            // the glyph and its text centre on the widget itself. Inside the
            // stack they would centre on the leftover space below the title,
            // which reads as slightly too low.
            if let emptyState {
                emptyStateView(emptyState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .padding(contentPadding)
        // Anchors the whole card to the top and clips what will not fit. When
        // several titles wrap at once the rows can outgrow the widget, and
        // without this the overflow is split across both edges — taking the
        // filter's name off the top of its own widget.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .containerBackground(.background, for: .widget)
        // Anywhere that is not a circle, a title or the add button. Routed
        // through our own scheme because a widget's URL is handed to its own
        // app, not opened system-wide.
        .widgetURL(URL(string: "quickreminders://reminders"))
    }

    // MARK: - Header

    private var header: some View {
        // Four things share one line on a 170pt card, so the spacing and the
        // symbol's box are both tighter there than they need to be elsewhere.
        HStack(spacing: family == .systemSmall ? 4 : 6) {
            Image(systemName: entry.filter?.symbolName ?? "line.3.horizontal.decrease.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                // Symbols vary wildly in width; a fixed box keeps the title's
                // left edge steady across filters.
                .frame(width: family == .systemSmall ? 17 : 20, alignment: .leading)

            Text(entry.filter?.name ?? "No Filter")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                // Shrinks before it truncates: a scaled-down name still reads,
                // a clipped one does not.
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            // Beside the name and unemphasised: it qualifies the filter rather
            // than competing with it for the eye.
            if !entry.items.isEmpty {
                Text("\(entry.items.count)")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    // Outranks the spacer, or a long filter name squeezes the
                    // count out of the header entirely.
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            if entry.showsAddButton {
                addButton
            }
        }
    }

    private struct EmptyState {
        let title: String
        let detail: String?
        let symbol: String
    }

    private var emptyState: EmptyState? {
        switch entry.status {
        case .noFilters:
            EmptyState(
                title: "No Filters",
                detail: "Create one in Quick Reminders settings.",
                symbol: "line.3.horizontal.decrease.circle"
            )
        case .missingFilter:
            EmptyState(
                title: "Filter Not Found",
                detail: "Pick one again in this widget's settings.",
                symbol: "questionmark.circle"
            )
        case .awaitingApp:
            // Not "no access": the app may simply never have run. Either way the
            // fix is the same and it lives in the app, not here.
            EmptyState(
                title: "Waiting for Quick Reminders",
                detail: "Open it once to load your reminders.",
                symbol: "arrow.trianglehead.2.clockwise"
            )
        case .ok, .stale:
            entry.items.isEmpty
                ? EmptyState(title: "All Clear", detail: staleNote, symbol: "checkmark.circle")
                : nil
        }
    }

    /// Rows, at whatever count actually fits.
    ///
    /// Titles wrap to two lines, so a row's height is not known in advance and a
    /// fixed count can outgrow the card. `ViewThatFits` tries the full set first
    /// and steps down until one fits, which keeps the "+N more" honest instead of
    /// clipping a row in half.
    private var rows: some View {
        ViewThatFits(in: .vertical) {
            rowStack(limit: rowLimit)
            rowStack(limit: rowLimit - 1)
            rowStack(limit: max(1, rowLimit - 2))
        }
    }

    private func rowStack(limit: Int) -> some View {
        let shown = Array(entry.items.prefix(limit))
        let overflow = entry.items.count - shown.count

        return VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(shown) { item in
                TaskRow(
                    item: item,
                    showsTrailingDetail: showsTrailingDetail,
                    isPending: entry.pendingIDs.contains(item.id),
                    tint: tint
                )
            }

            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 31)
            }

            if let staleNote {
                Text(staleNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 31)
            }
        }
    }

    /// Shown only once the rows are old enough to mislead. Rows are still drawn:
    /// yesterday's list beats a blank card.
    private var staleNote: String? {
        guard case .stale(let since) = entry.status else { return nil }
        return "Last updated \(since.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Empty state

    /// The system's empty-state shape — one large glyph, a title under it and an
    /// optional line of explanation, centred together.
    private func emptyStateView(_ state: EmptyState) -> some View {
        VStack(spacing: family == .systemSmall ? 6 : 8) {
            Image(systemName: state.symbol)
                .font(.system(size: emptyGlyphSize, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 3) {
                Text(state.title)
                    .font(.system(size: emptyTitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if let detail = state.detail {
                    Text(detail)
                        .font(.system(size: emptyDetailSize))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
        }
        .multilineTextAlignment(.center)
    }

    private var emptyGlyphSize: CGFloat {
        switch family {
        case .systemSmall: 30
        case .systemLarge: 46
        default: 34
        }
    }

    private var emptyTitleSize: CGFloat {
        switch family {
        case .systemSmall: 12
        case .systemLarge: 16
        default: 13
        }
    }

    private var emptyDetailSize: CGFloat {
        switch family {
        case .systemSmall: 10
        case .systemLarge: 12
        default: 11
        }
    }

    // MARK: - Add

    /// A `Link` rather than an intent: adding needs the quick entry panel, which
    /// only the app can show. `quickreminders://new` is the scheme the app
    /// already registers for launchers.
    private var addButton: some View {
        Link(destination: URL(string: "quickreminders://new")!) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct TaskRow: View {
    let item: TaskItem
    let showsTrailingDetail: Bool
    /// Ticked, but still inside the undo window — nothing has been written yet.
    var isPending = false
    var tint: Color = .accentColor

    private var isOverdue: Bool { DueDateFormat.isOverdue(item) }

    private var isChecked: Bool { isPending || item.isCompleted }

    /// Titles can run to two lines, so everything aligns to the top and the
    /// first line is nudged down to sit level with the circle beside it rather
    /// than drifting when a title wraps.
    private static let firstLineOffset: CGFloat = 2

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(intent: CompleteTaskIntent(taskID: item.id, completed: !item.isCompleted)) {
                Image(systemName: isChecked ? "inset.filled.circle" : "circle")
                    .font(.system(size: 21, weight: .light))
                    // Filled and tinted the moment it is tapped, so the tick is
                    // visible immediately even though it has not been sent.
                    .foregroundStyle(isChecked ? tint : Color.secondary.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Opens this reminder in Reminders.app. A Link rather than the
            // widget-wide URL so the row you actually clicked is the one that
            // opens.
            Link(destination: item.widgetLinkURL) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(isChecked ? .secondary : .primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Self.firstLineOffset)
                        // Claims the whole remaining width rather than only its
                        // ideal width, which both pins the trailing glyphs to the
                        // right edge and stops short titles wrapping for no reason.
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsTrailingDetail, let due = DueDateFormat.label(for: item) {
                        Text(due)
                            .font(.system(size: 13))
                            .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                            .lineLimit(1)
                            .padding(.top, Self.firstLineOffset + 1)
                    }

                    // Shown at every size, including the small one where there is
                    // no room for a date: whether something recurs changes what
                    // ticking it off means.
                    if item.isRepeating {
                        Image(systemName: "repeat")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, Self.firstLineOffset + 2)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
