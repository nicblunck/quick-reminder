import AppIntents
import Foundation
import WidgetKit

struct FilterEntry: TimelineEntry {

    /// What the widget should say when it has no rows. These look identical on
    /// the desktop but need opposite fixes, so they are never collapsed into one
    /// empty state.
    enum Status: Equatable {
        /// Rows are current.
        case ok
        /// No filters have been created yet.
        case noFilters
        /// This widget names a filter that has since been deleted.
        case missingFilter
        /// The app has never published — it has not run, or has no Reminders access.
        case awaitingApp
        /// Rows are real but were published a long time ago.
        case stale(since: Date)
    }

    let date: Date
    let filter: TaskFilter?
    let items: [TaskItem]
    let status: Status
    let showsAddButton: Bool
    /// Ticked, but not sent yet — still inside the undo window.
    var pendingIDs: Set<String> = []

    static func placeholder(_ filter: TaskFilter) -> FilterEntry {
        FilterEntry(
            date: Date(),
            filter: filter,
            items: SampleTasks.items,
            status: .ok,
            showsAddButton: filter.showsAddButton
        )
    }
}

/// Canned rows for the widget gallery, where nothing real is read.
enum SampleTasks {
    static let items: [TaskItem] = [
        TaskItem(
            id: "sample-1", title: "Book Hours", notes: nil, isCompleted: false, priority: .none,
            dueDate: Calendar.current.date(bySettingHour: 17, minute: 45, second: 0, of: Date()),
            hasTime: true, startDate: nil, isRepeating: true,
            listID: "sample", listTitle: "Work", listColor: nil
        ),
        TaskItem(
            id: "sample-2", title: "Check on Groceries", notes: nil, isCompleted: false,
            priority: .none, dueDate: Date(), hasTime: false, startDate: nil, isRepeating: false,
            listID: "sample", listTitle: "Home", listColor: nil
        ),
    ]
}

/// Reads what the app published; never touches EventKit.
///
/// The extension is sandboxed and holds no Reminders grant, so its own
/// connection to the Reminders daemon is refused with Mach error 4099 — and a
/// widget cannot show a TCC prompt to fix that. All the querying happens in the
/// app; see `WidgetSnapshotPublisher`.
struct FilterTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> FilterEntry {
        .placeholder(FilterStorage.load().first ?? TaskFilter.defaults()[0])
    }

    func snapshot(for configuration: SelectFilterIntent, in context: Context) async -> FilterEntry {
        // The gallery preview must never depend on the app having run, or the
        // widget looks broken before it has even been added.
        if context.isPreview {
            if case .filter(let filter) = resolve(configuration) { return .placeholder(filter) }
            return .placeholder(TaskFilter.defaults()[0])
        }
        return entry(for: configuration)
    }

    func timeline(for configuration: SelectFilterIntent, in context: Context) async -> Timeline<FilterEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(nextRefresh()))
    }

    // MARK: - Helpers

    private enum Resolved {
        case filter(TaskFilter)
        /// Configured against a filter that no longer exists.
        case missing
        case none
    }

    /// An unconfigured widget falls back to the first saved filter, so one added
    /// before anything was chosen still shows something real. A widget that names
    /// a *deleted* filter does not fall back: silently showing a different list
    /// than the one asked for is worse than saying the selection is gone.
    private func resolve(_ configuration: SelectFilterIntent) -> Resolved {
        if let id = configuration.filter?.id {
            guard let match = FilterStorage.filter(id: id) else { return .missing }
            return .filter(match)
        }
        return FilterStorage.load().first.map(Resolved.filter) ?? .none
    }

    private func entry(for configuration: SelectFilterIntent) -> FilterEntry {
        let filter: TaskFilter
        switch resolve(configuration) {
        case .filter(let resolved):
            filter = resolved
        case .missing:
            return FilterEntry(
                date: Date(), filter: nil, items: [], status: .missingFilter, showsAddButton: false
            )
        case .none:
            return FilterEntry(
                date: Date(), filter: nil, items: [], status: .noFilters, showsAddButton: false
            )
        }

        guard let snapshot = FilterStorage.loadSnapshot() else {
            return FilterEntry(
                date: Date(), filter: filter, items: [], status: .awaitingApp, showsAddButton: false
            )
        }

        return FilterEntry(
            date: Date(),
            filter: filter,
            items: snapshot.tasks(for: filter.id),
            status: snapshot.isStale ? .stale(since: snapshot.generated) : .ok,
            // The widget's own switch can only take the button away, never add
            // one to a filter that has opted out.
            showsAddButton: filter.showsAddButton && configuration.showsAddButton,
            pendingIDs: FilterStorage.pendingCompletionIDs()
        )
    }

    /// Only a backstop. The app reloads timelines directly whenever reminders or
    /// filters change, so this exists for the case where nothing changed all day
    /// but "due today" stopped meaning what it did — midnight.
    private func nextRefresh(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let halfHour = now.addingTimeInterval(30 * 60)
        guard let midnight = calendar.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) else { return halfHour }
        return min(halfHour, midnight)
    }
}
