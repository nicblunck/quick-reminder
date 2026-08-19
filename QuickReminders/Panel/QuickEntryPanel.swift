import AppKit

/// The floating capture window.
///
/// The window itself provides the rounded shape and the shadow — that is what a
/// titled window with a hidden titlebar already does — and an `NSVisualEffectView`
/// provides the Liquid Glass backdrop. Nothing rounds or shadows anything in
/// SwiftUI; drawing a second rounded card inside a window that is already rounded
/// leaves a seam wherever the two curves disagree.
///
/// `.nonactivatingPanel` keeps the app underneath from being disturbed, but such a
/// panel refuses key status by default, which would leave the text field unable to
/// accept typing. Hence `canBecomeKey`.
final class QuickEntryPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Without this, Esc would not reach the SwiftUI content in a panel that has
    /// no menu-bar-owning main window.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    var onCancel: (() -> Void)?
}
