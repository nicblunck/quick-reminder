import AppKit

// Plain AppKit entry point rather than a SwiftUI `App`.
//
// Everything structural here is already AppKit — the status item, the floating
// panel, the settings window — and SwiftUI's `Settings` scene can only be opened
// through an undocumented `showSettingsWindow:` responder action, which does not
// reliably work from an app delegate. Owning the window removes that dependency.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
