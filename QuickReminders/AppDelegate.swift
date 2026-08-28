import EventKit
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let service = RemindersService()
    let preferences = Preferences()
    let updater = UpdaterService()
    let filterStore = FilterStore()
    /// The widgets cannot read EventKit themselves, so the app publishes for them.
    private lazy var snapshotPublisher = WidgetSnapshotPublisher(
        filters: { [filterStore] in filterStore.filters }
    )
    /// Lazy, not built in `applicationDidFinishLaunching`: a `quickreminders://`
    /// URL is delivered during AppKit's window-restoration pass, which runs
    /// *before* that method, and touching a nil controller there traps.
    private lazy var panelController = PanelController { [service, preferences] context in
        AnyView(QuickEntryView(
            service: service,
            preferences: preferences,
            initialText: context.prefill,
            dismiss: context.dismiss,
            setPinned: context.setPinned
        ))
    }
    /// Held strongly: the status item vanishes if it is not retained.
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var filtersWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        HotkeyManager.onToggle { [weak self] in
            self?.panelController.toggle()
        }

        // Ask at launch, not on first panel open: a `quickreminders://add` deep
        // link saves without any UI, and would otherwise fail on a cold start.
        service.refreshAccessStatus()
        Task {
            if service.access == .undetermined {
                await service.requestAccess()
            } else if service.access == .granted {
                service.loadLists()
            }
            // Seeded once access is settled, so the Filters tab and the widget
            // gallery are never an empty page on a first run.
            filterStore.seedIfEmpty()
            await snapshotPublisher.refresh()
        }

        // Editing a filter changes what the widget should show, not merely when.
        filterStore.onChange = { [weak self] in self?.snapshotPublisher.setNeedsRefresh() }
        observeReminderChanges()
        snapshotPublisher.startWatchingContainer()
    }

    /// Widget timelines are scheduled half-hourly, which is far too slow to feel
    /// live when a reminder is ticked off in Reminders.app. The app is running
    /// anyway, so it re-publishes whenever the store changes.
    private func observeReminderChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapshotPublisher.setNeedsRefresh() }
        }
    }

    // MARK: - Menu bar

    /// A plain `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because
    /// `MenuBarExtra` cannot tell a left click from a right click.
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Quick Reminders")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Quick Reminders — click to capture, right-click for more"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            showContextMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: ""
        )
        checkForUpdates.target = self
        checkForUpdates.isEnabled = updater.canCheckForUpdates
        menu.addItem(checkForUpdates)

        let filters = NSMenuItem(
            title: "Filters…", action: #selector(openFiltersAction), keyEquivalent: "f"
        )
        filters.target = self
        menu.addItem(filters)

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Quick Reminders", action: #selector(quitApp), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        // Attaching the menu and clicking gives correct placement and the usual
        // highlighted-button look; it is then cleared so the next left click
        // reaches our action instead of reopening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func checkForUpdatesAction() {
        updater.checkForUpdates()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func openFiltersAction() {
        openFilters()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(
                service: service, preferences: preferences, updater: updater,
                openFilters: { [weak self] in self?.openFilters() }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Quick Reminders Settings"
        window.styleMask = [.titled, .closable]
        // Kept alive so reopening restores the same window instead of building
        // a new one each time.
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    /// Filters get a window of their own: a condition tree beside a list of
    /// filters needs far more room than the settings form, and cramming both
    /// into one window forces the settings pane to be as wide as the widest
    /// thing in it.
    private func openFilters() {
        NSApp.activate(ignoringOtherApps: true)

        if let filtersWindow {
            filtersWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: FiltersSettingsView(store: filterStore, service: service)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Filters"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Kept alive so reopening restores the same window, and the selected
        // filter with it.
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        filtersWindow = window
    }

    // MARK: - Entry points

    func showPanel(prefill: String = "") {
        panelController.show(prefill: prefill)
    }

    /// Two deep links, for launchers like Raycast, Alfred or Shortcuts:
    ///
    ///   `quickreminders://new?text=call+dentist+tomorrow+5pm`  opens the panel, pre-filled
    ///   `quickreminders://add?text=call+dentist+tomorrow+5pm`  saves straight away, no UI
    ///   `quickreminders://settings`                            opens settings
    ///   `quickreminders://filters`                             opens the filters window
    ///
    /// A failed silent add falls back to opening the panel with the text intact,
    /// so nothing the user typed is ever lost.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "quickreminders" else { return }
        let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "text" }?.value ?? ""

        switch url.host() {
        case "add" where !text.isEmpty:
            silentAdd(text)
        case "settings":
            openSettings()
        case "filters":
            openFilters()
        default:
            showPanel(prefill: text)
        }
    }

    private func silentAdd(_ text: String) {
        let parsed = ReminderParser.parse(text)
        service.defaultTime = preferences.defaultTime
        let draft = ReminderDraft(
            title: parsed.cleanedTitle,
            listID: preferences.preferredListID(fallback: service.defaultListID),
            dueDate: parsed.dueDate,
            hasTime: parsed.hasTime,
            priority: parsed.priority
        )
        do {
            try service.save(draft)
        } catch {
            NSLog("Quick Reminders: silent add failed — \(error.localizedDescription)")
            showPanel(prefill: text)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
