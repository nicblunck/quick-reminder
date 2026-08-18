import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default ⌥Space. Rebindable from Settings via `KeyboardShortcuts.Recorder`.
    static let toggleQuickEntry = Self("toggleQuickEntry", default: .init(.space, modifiers: [.option]))
}

/// Thin wrapper so the app shell doesn't reach into KeyboardShortcuts directly.
///
/// KeyboardShortcuts is built on Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission — unlike `NSEvent.addGlobalMonitorForEvents`.
@MainActor
enum HotkeyManager {
    static func onToggle(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleQuickEntry, action: handler)
    }

    static func resetToDefault() {
        KeyboardShortcuts.reset(.toggleQuickEntry)
    }
}
