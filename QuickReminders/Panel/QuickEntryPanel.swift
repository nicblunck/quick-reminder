import AppKit
import SwiftUI

/// The floating capture window.
///
/// The shape has exactly one owner: the mask on the backdrop view. The window is
/// borderless, transparent and non-opaque, so it contributes no rectangle and no
/// second curve of its own — AppKit derives the shadow from the masked content's
/// alpha, which is why the shadow follows the corners instead of squaring them
/// off. Nothing rounds or shadows anything in SwiftUI; a rounded card drawn
/// inside an already-rounded window leaves a seam wherever the two curves
/// disagree.
///
/// `.nonactivatingPanel` keeps the app underneath from being disturbed, but such a
/// panel refuses key status by default, which would leave the text field unable to
/// accept typing. Hence `canBecomeKey`.
final class QuickEntryPanel: NSPanel {

    /// Deliberately well past the system window radius. A capture panel this
    /// small reads as a card rather than a document window, and the softer
    /// corner is what makes it read that way.
    static let cornerRadius: CGFloat = 22

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

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

    /// Without this, Esc would not reach the SwiftUI content in a panel that has
    /// no menu-bar-owning main window.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    var onCancel: (() -> Void)?

    /// A resizable stencil of the panel's shape, for `NSVisualEffectView.maskImage`.
    ///
    /// The mask has to go through that property rather than a layer `cornerRadius`:
    /// a `.behindWindow` blur is composited by the window server, which only knows
    /// about the mask image — and so does the shadow that gets derived from it.
    ///
    /// The corner is continuous, matching the system's window curve rather than a
    /// plain arc, and `Path` is the one place to get that exact curve for free.
    /// A continuous corner runs further along each edge than its radius, so the
    /// caps are twice the radius; slicing at the radius itself would cut through
    /// the curve and stretch the remainder across the flat edges.
    static func backdropMask() -> NSImage {
        let cap = cornerRadius * 2
        let edge = cap * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(
                Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous).cgPath
            )
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }
}
