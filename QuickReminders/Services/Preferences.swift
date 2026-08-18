import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let listMode = "listMode"
        static let fixedListID = "fixedListID"
        static let lastUsedListID = "lastUsedListID"
        static let defaultHour = "defaultHour"
        static let defaultMinute = "defaultMinute"
        static let submitShortcut = "submitShortcut"
    }

    enum ListMode: String, CaseIterable, Identifiable {
        case lastUsed
        case fixed

        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastUsed: "Last used list"
            case .fixed: "Always this list"
            }
        }
    }

    enum SubmitShortcut: String, CaseIterable, Identifiable {
        case commandReturn
        case returnKey

        var id: String { rawValue }

        var label: String {
            switch self {
            case .commandReturn: "⌘ Return"
            case .returnKey: "Return"
            }
        }

        /// Rendered on the Add button.
        var hint: String {
            switch self {
            case .commandReturn: "⌘↩"
            case .returnKey: "↩"
            }
        }
    }

    private let defaults: UserDefaults

    var listMode: ListMode { didSet { defaults.set(listMode.rawValue, forKey: Key.listMode) } }
    var fixedListID: String? { didSet { defaults.set(fixedListID, forKey: Key.fixedListID) } }
    var lastUsedListID: String? { didSet { defaults.set(lastUsedListID, forKey: Key.lastUsedListID) } }
    var defaultHour: Int { didSet { defaults.set(defaultHour, forKey: Key.defaultHour) } }
    var defaultMinute: Int { didSet { defaults.set(defaultMinute, forKey: Key.defaultMinute) } }
    var submitShortcut: SubmitShortcut {
        didSet { defaults.set(submitShortcut.rawValue, forKey: Key.submitShortcut) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.defaultHour: 9, Key.defaultMinute: 0])
        listMode = ListMode(rawValue: defaults.string(forKey: Key.listMode) ?? "") ?? .lastUsed
        fixedListID = defaults.string(forKey: Key.fixedListID)
        lastUsedListID = defaults.string(forKey: Key.lastUsedListID)
        defaultHour = defaults.integer(forKey: Key.defaultHour)
        defaultMinute = defaults.integer(forKey: Key.defaultMinute)
        submitShortcut = SubmitShortcut(rawValue: defaults.string(forKey: Key.submitShortcut) ?? "")
            ?? .commandReturn
    }

    /// Which list a freshly-opened panel should point at.
    func preferredListID(fallback: String?) -> String? {
        switch listMode {
        case .fixed: fixedListID ?? fallback
        case .lastUsed: lastUsedListID ?? fallback
        }
    }

    var defaultTime: (hour: Int, minute: Int) { (defaultHour, defaultMinute) }

    /// A `Date` today at the configured default time, for binding to a DatePicker.
    var defaultTimeAsDate: Date {
        get {
            Calendar.current.date(
                bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: Date()
            ) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            defaultHour = comps.hour ?? 9
            defaultMinute = comps.minute ?? 0
        }
    }
}
