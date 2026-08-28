import AppIntents
import WidgetKit

/// Ticking the circle on a widget row.
///
/// The extension cannot write to EventKit any more than it can read from it, so
/// this records the intent in the App Group and lets the app perform it. The app
/// watches that container and applies queued completions within a moment, so the
/// round trip is invisible in practice — and nothing steals focus, which is the
/// whole point of an interactive widget.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let openAppWhenRun = false

    @Parameter(title: "Reminder ID")
    var taskID: String

    @Parameter(title: "Completed")
    var completed: Bool

    init() {}

    init(taskID: String, completed: Bool) {
        self.taskID = taskID
        self.completed = completed
    }

    func perform() async throws -> some IntentResult {
        // Tapping a circle that is already filled takes the tick back. That is
        // the whole point of queuing rather than writing at once: for a couple
        // of seconds the reminder is marked but nothing has happened yet.
        if FilterStorage.hasPendingCompletion(for: taskID) {
            FilterStorage.cancelPendingCompletion(for: taskID)
        } else {
            FilterStorage.enqueueCompletion(
                PendingCompletion(taskID: taskID, completed: completed, requested: Date())
            )
        }
        FilterStorage.reloadWidgets()
        return .result()
    }
}
