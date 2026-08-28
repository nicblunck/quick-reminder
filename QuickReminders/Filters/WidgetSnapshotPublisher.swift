import Foundation

/// Does the widgets' EventKit work for them.
///
/// A widget extension is sandboxed and holds no Reminders grant, so its own
/// connection to the Reminders daemon is refused (Mach 4099) and it has no way
/// to prompt for one. The app has the grant and runs at login anyway, so it
/// evaluates every filter here and leaves the results in the App Group. It also
/// drains the completions the widget could only queue.
@MainActor
final class WidgetSnapshotPublisher {

    private let query: ReminderQuery
    private let filters: () -> [TaskFilter]

    /// Coalesces the burst of `EKEventStoreChanged` notifications a single edit
    /// in Reminders.app produces — without it, ticking one box republishes four
    /// or five times.
    private var pendingRefresh: Task<Void, Never>?
    private var containerWatch: DispatchSourceFileSystemObject?

    init(query: ReminderQuery = ReminderQuery(), filters: @escaping () -> [TaskFilter]) {
        self.query = query
        self.filters = filters
    }

    deinit { containerWatch?.cancel() }

    // MARK: - Publishing

    /// Debounced. Safe to call from every change notification.
    func setNeedsRefresh(after delay: Duration = .milliseconds(400)) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        guard query.hasAccess else {
            NSLog("Quick Reminders: no Reminders access — widgets cannot be published.")
            return
        }

        let nextMaturity = await applyPendingCompletions()

        let all = await query.fetchTasks(includeCompleted: true)
        let current = filters()

        var byFilter: [UUID: [TaskItem]] = [:]
        for filter in current {
            // Evaluated against the same fetch for every filter: one EventKit
            // round trip regardless of how many filters exist.
            byFilter[filter.id] = FilterEvaluator.evaluate(filter, against: all)
        }

        FilterStorage.saveSnapshot(WidgetSnapshot(generated: Date(), tasksByFilter: byFilter))
        FilterStorage.reloadWidgets()

        // One line per publish. The widget cannot report on itself — it has no
        // console and no way to surface a failure — so this is the only place
        // the pipeline's health is visible.
        let summary = current.map { "\($0.name)=\(byFilter[$0.id]?.count ?? 0)" }.joined(separator: " ")
        NSLog("Quick Reminders: published \(current.count) filters from \(all.count) reminders — \(summary)")

        // Something is still inside its undo window. Come back when it is not,
        // or it would sit filled until the next unrelated change.
        if let nextMaturity {
            let seconds = max(0.05, nextMaturity.timeIntervalSinceNow)
            setNeedsRefresh(after: .milliseconds(Int(seconds * 1000)))
        }
    }

    // MARK: - Completions queued by the widget

    /// The widget writes what it wanted to do; this is where it actually happens
    /// — but only once the undo window has passed.
    ///
    /// Returns when the earliest still-waiting tick comes due, so the caller can
    /// schedule itself to run again then.
    private func applyPendingCompletions() async -> Date? {
        let queue = FilterStorage.loadPendingCompletions()
        guard !queue.isEmpty else { return nil }

        let now = Date()
        let ready = queue.filter { $0.isMature(at: now) }
        let waiting = queue.filter { !$0.isMature(at: now) }

        var applied: [PendingCompletion] = []
        for pending in ready {
            do {
                try query.setCompleted(pending.completed, forTaskWithID: pending.taskID)
                applied.append(pending)
            } catch {
                NSLog("Quick Reminders: could not complete \(pending.taskID) — \(error.localizedDescription)")
                // Dropped rather than retried forever: a reminder deleted in
                // Reminders.app would otherwise wedge the queue permanently.
                applied.append(pending)
            }
        }
        FilterStorage.clearPendingCompletions(applied)
        return waiting.map(\.maturity).min()
    }

    // MARK: - Watching for the widget's writes

    /// The widget queues a completion by writing into the container's inbox.
    /// Watching it means the tick is applied in about as long as it takes to
    /// draw, rather than waiting for the next timeline refresh.
    ///
    /// The inbox and not the container itself: the publisher's own snapshot
    /// writes land beside it, and watching those would have the app republishing
    /// in response to its own output, forever.
    func startWatchingContainer() {
        guard containerWatch == nil, let inbox = FilterStorage.inboxURL else { return }

        let descriptor = open(inbox.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Quick Reminders: could not watch the app group inbox.")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .attrib], queue: .main
        )
        source.setEventHandler { [weak self] in
            // Short debounce, not the default: this is a user waiting to see a
            // row disappear, and the write that woke us is already complete.
            self?.setNeedsRefresh(after: .milliseconds(120))
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        containerWatch = source
    }
}
