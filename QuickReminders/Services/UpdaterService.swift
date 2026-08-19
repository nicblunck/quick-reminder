import Observation
import Sparkle

/// Wraps Sparkle so the rest of the app never imports it.
///
/// `SPUStandardUpdaterController` starts the updater and owns the standard UI.
/// Sparkle's own state is KVO, not Observation, so the two published values are
/// mirrored onto `@Observable` properties that SwiftUI can watch.
@MainActor
@Observable
final class UpdaterService {

    /// False while an update check is already running, so the menu item and the
    /// settings button can disable rather than stack up checks.
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != controller.updater.automaticallyChecksForUpdates
            else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        // `startingUpdater: true` schedules the background check itself; nothing
        // else needs to poll.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        // Both values are read again through KVO rather than trusted from init:
        // the updater is still starting at this point, so an immediate read can
        // return the default instead of the resolved setting.
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
                [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) {
                [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                }
            },
        ]
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// When the last check ran, for the settings screen.
    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
