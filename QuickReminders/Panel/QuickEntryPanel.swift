import AppKit

/// The floating capture window.
///
/// Two non-obvious requirements:
///  - `.nonactivatingPanel` keeps the app underneath from being visually
///    disturbed, but such a panel refuses key status by default, which would
///    leave the text field unable to accept typing. Hence `canBecomeKey`.
///  - The window is transparent and exactly the size of the card; the rounded
///    shape and its shadow come from the content's alpha, not a drawn rectangle.
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

        backgroundColor = .clear
        isOpaque = false
        // AppKit's own shadow, shaped from the content's alpha, rather than a
        // hand-drawn one inside a transparent margin.
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Without this, ⌘W / ⌘. and plain Esc would not reach the SwiftUI content
    /// in a panel that has no menu-bar-owning main window.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    var onCancel: (() -> Void)?
}
