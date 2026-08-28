import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// A filter's matches, evaluated by the app and left where the widget can read
/// them.
///
/// The widget cannot query EventKit itself: its XPC connection to the Reminders
/// daemon is refused with Mach error 4099, because a sandboxed extension has no
/// TCC grant of its own and no way to ask for one. So the app — which does have
/// the grant, and is running anyway — does the querying and leaves the answer
/// here.
struct WidgetSnapshot: Codable, Sendable {
    var generated: Date
    var tasksByFilter: [UUID: [TaskItem]]

    /// Older than this and the widget says so rather than showing stale rows as
    /// if they were current. Generous, because the app republishes on every
    /// store change and this only bites when it has not run at all.
    static let staleAfter: TimeInterval = 60 * 60 * 6

    var isStale: Bool { Date().timeIntervalSince(generated) > Self.staleAfter }

    func tasks(for filterID: UUID) -> [TaskItem] { tasksByFilter[filterID] ?? [] }
}

/// A completion the widget recorded but has not sent yet.
///
/// The delay is deliberate, not just a consequence of the widget being unable to
/// write: for `grace` seconds the circle sits filled and the row stays put, and
/// tapping it again takes the tick back. Only after that does the app write it.
struct PendingCompletion: Codable, Sendable, Hashable {
    var taskID: String
    var completed: Bool
    var requested: Date

    /// Long enough to notice a mistake and undo it, short enough that the row
    /// does not feel stuck.
    static let grace: TimeInterval = 2

    func isMature(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(requested) >= Self.grace
    }

    var maturity: Date { requested.addingTimeInterval(Self.grace) }
}

/// The App Group container, and the one place that knows its identifier.
///
/// Plain files rather than `UserDefaults(suiteName:)`. A shared suite is the
/// obvious choice and it does not work here: cfprefsd refuses the group domain
/// with "Using kCFPreferencesAnyUser with a container is only allowed for System
/// Containers" and detaches, which makes reads unreliable in the extension.
/// A JSON file in the same container has none of that ambiguity.
enum FilterStorage {

    static let appGroupID = "U4K77TMBRU.group.com.nicolasblunck.QuickReminders"

    /// Nil only when the entitlement is missing or misspelled — worth shouting
    /// about, because every widget would otherwise just look empty.
    static var containerURL: URL? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            NSLog("Quick Reminders: app group \(appGroupID) is unavailable — check entitlements.")
            return nil
        }
        return url
    }

    private static func url(_ name: String) -> URL? {
        containerURL?.appendingPathComponent(name, isDirectory: false)
    }

    private static var filtersURL: URL? { url("filters.json") }
    private static var snapshotURL: URL? { url("snapshot.json") }

    /// Everything the *widget* writes lives in its own subdirectory, so the app
    /// can watch for the widget's writes without waking itself up on its own
    /// snapshot rewrites — which is an endless publish loop.
    static var inboxURL: URL? {
        guard let inbox = containerURL?.appendingPathComponent("inbox", isDirectory: true)
        else { return nil }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private static var completionsURL: URL? {
        inboxURL?.appendingPathComponent("pending-completions.json", isDirectory: false)
    }

    // MARK: - Generic IO

    private static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("Quick Reminders: could not decode \(url.lastPathComponent) — \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private static func write<T: Encodable>(_ value: T, to url: URL?) -> Bool {
        guard let url else { return false }
        do {
            // Atomic, because the widget may be reading the same file in another
            // process at the moment the app rewrites it.
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Quick Reminders: could not write \(url.lastPathComponent) — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Filters

    static func load() -> [TaskFilter] { read([TaskFilter].self, from: filtersURL) ?? [] }

    static func save(_ filters: [TaskFilter]) { write(filters, to: filtersURL) }

    static func filter(id: UUID) -> TaskFilter? { load().first { $0.id == id } }

    // MARK: - Snapshot

    static func loadSnapshot() -> WidgetSnapshot? { read(WidgetSnapshot.self, from: snapshotURL) }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) { write(snapshot, to: snapshotURL) }

    // MARK: - Pending completions

    static func loadPendingCompletions() -> [PendingCompletion] {
        read([PendingCompletion].self, from: completionsURL) ?? []
    }

    /// Appended by the widget. Last write for a given reminder wins, so tapping
    /// a circle twice in quick succession settles on the final state rather than
    /// queuing two conflicting edits.
    static func enqueueCompletion(_ pending: PendingCompletion) {
        var queue = loadPendingCompletions().filter { $0.taskID != pending.taskID }
        queue.append(pending)
        write(queue, to: completionsURL)
    }

    static func pendingCompletionIDs() -> Set<String> {
        Set(loadPendingCompletions().map(\.taskID))
    }

    static func hasPendingCompletion(for taskID: String) -> Bool {
        loadPendingCompletions().contains { $0.taskID == taskID }
    }

    /// The undo. Tapping a circle that is already waiting takes the tick back
    /// before it is ever written.
    static func cancelPendingCompletion(for taskID: String) {
        let queue = loadPendingCompletions()
        let remaining = queue.filter { $0.taskID != taskID }
        guard remaining.count != queue.count else { return }
        write(remaining, to: completionsURL)
    }

    static func clearPendingCompletions(_ applied: [PendingCompletion]) {
        let appliedIDs = Set(applied.map(\.taskID))
        let queue = loadPendingCompletions()
        let remaining = queue.filter { !appliedIDs.contains($0.taskID) }
        // Writing an unchanged queue would wake the app's own watcher for
        // nothing, costing an extra publish per drain.
        guard remaining.count != queue.count else { return }
        write(remaining, to: completionsURL)
    }

    // MARK: - Widgets

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
