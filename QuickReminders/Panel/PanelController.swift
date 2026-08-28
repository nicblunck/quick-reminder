import AppKit
import SwiftUI

/// What the panel hands its content: the text to start from, a way to close, and
/// a way to say "hold this open".
@MainActor
struct PanelContext {
    var prefill: String
    var dismiss: () -> Void
    var setPinned: (Bool) -> Void
}

/// Owns the lifetime and placement of the quick entry panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    private var panel: QuickEntryPanel?
    /// The SwiftUI host, kept because it — not the glass backdrop wrapping it —
    /// is the only view that can say how big the card wants to be.
    private weak var hosting: NSView?
    private let makeContent: (PanelContext) -> AnyView
    private var pendingPrefill = ""
    private var isDismissing = false
    /// Set from the pin button. Suppresses only the automatic dismissal — Esc,
    /// the close button, the hotkey and a successful save all still close.
    private var isPinned = false
    /// Enough travel to read as motion; a smaller lift just looks like a stutter.
    private static let riseDistance: CGFloat = 18
    private static let appearDuration: TimeInterval = 0.24
    private static let dismissDuration: TimeInterval = 0.09
    private static let dismissDrop: CGFloat = 8

    /// - Parameter content: builds the SwiftUI body from the panel's context.
    init(content: @escaping (PanelContext) -> AnyView) {
        self.makeContent = content
        super.init()
        observeDeactivation()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible, !isDismissing { reset() } else { show() }
    }

    func show(prefill: String = "") {
        // Finish any in-flight dismissal before reusing the controller, or the
        // fade-out's completion would tear down the panel we are about to show.
        if isDismissing { tearDown() }
        // A different prefill needs a fresh view, not the recycled one.
        if prefill != pendingPrefill { tearDown() }
        pendingPrefill = prefill
        let panel = panel ?? makePanel()
        self.panel = panel

        sizeToFit(panel)
        position(panel)
        // A non-activating panel still needs the app frontmost for the text
        // field to reliably take first responder from a background process.
        NSApp.activate(ignoringOtherApps: true)

        // Fade and rise into place. Deliberately no scale: AppKit cannot scale a
        // window, and scaling the card in SwiftUI instead would shrink it away
        // from the shape AppKit derived the shadow from, so the shadow would hang
        // in place at full size while the card moved. Travel and easing carry the
        // motion instead, and both are things AppKit animates cleanly.
        // Position only — the opacity is deliberately NOT animated. Every frame
        // of an alphaValue change makes the Liquid Glass material re-sample its
        // backdrop, which reads as flicker. It was always there; a longer
        // animation only made it long enough to notice.
        let destination = panel.frame.origin
        panel.alphaValue = 1
        panel.setFrameOrigin(NSPoint(x: destination.x, y: destination.y - Self.riseDistance))
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.appearDuration
            // Leaves fast and decelerates hard into place — the tail of a spring
            // without the overshoot that would need room to grow into.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrameOrigin(destination)
        }

    }

    /// Fades out, then tears down so the next capture starts from a clean draft.
    func reset() {
        guard let panel, !isDismissing else { return }
        isDismissing = true

        // Retreats the way it arrived, and faster: dismissal should feel
        // immediate rather than played back.
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.dismissDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(
                NSPoint(x: origin.x, y: origin.y - Self.dismissDrop)
            )
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.tearDown() }
        })
    }

    private func tearDown() {
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        isDismissing = false
        // Each capture starts unpinned.
        isPinned = false
    }

    private func makePanel() -> QuickEntryPanel {
        let panel = QuickEntryPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200))

        // The Liquid Glass backdrop for the whole window, and the one thing that
        // gives the panel its shape. SwiftUI draws only content on top of it —
        // no material, no rounding, no shadow there.
        //
        // This has to be a glass view rather than an `NSVisualEffectView`: the
        // visual effect materials only blur what is behind them, so the rim comes
        // out flat. Glass additionally refracts the backdrop through the edge and
        // lights it, which is the whole difference between frosted and glass.
        // Shape is a property here, so no mask image is involved.
        let backdrop = NSGlassEffectView()
        backdrop.cornerRadius = QuickEntryPanel.cornerRadius
        backdrop.style = .regular

        let hosting = NSHostingView(
            rootView: makeContent(
                PanelContext(
                    prefill: pendingPrefill,
                    dismiss: { [weak self] in self?.reset() },
                    setPinned: { [weak self] pinned in self?.isPinned = pinned }
                )
            )
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        // Nothing here should reserve room for window chrome the panel doesn't
        // have; without this an inset would leave an empty strip above the content.
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // The glass view sizes and clips whatever it is handed, so the content
        // goes through `contentView` rather than being added as a plain subview.
        backdrop.contentView = hosting
        self.hosting = hosting

        panel.contentView = PanelCardView(card: backdrop)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.reset() }
        return panel
    }

    /// SwiftUI decides the card's height (notes and URL fields expand it), so ask
    /// the hosting view what it wants before placing the window.
    ///
    /// It has to be the hosting view specifically, not the window's content view.
    /// The glass backdrop stretches whatever it is given to its own bounds, so its
    /// fitting size answers for the glass alone and comes back near nothing —
    /// which collapses the window to a stub.
    private func sizeToFit(_ panel: NSPanel) {
        guard let content = hosting else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        // The card is what SwiftUI measured; the window also carries the margin
        // the shadow falls into.
        let inset = QuickEntryPanel.cardInset * 2
        panel.setContentSize(
            NSSize(width: size.width + inset, height: size.height + inset)
        )

    }

    /// Centred horizontally on whichever screen holds the pointer, sitting a
    /// little above true centre the way Spotlight does.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.62 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    /// Dismiss when the user moves to another app — deliberately NOT on the panel
    /// merely losing key status. Menus, popovers (the graphical date picker) and
    /// notification banners all steal key focus without deactivating the app, and
    /// tearing the panel down for any of those loses whatever was typed.
    private func observeDeactivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoDismiss() }
        }
    }

    /// Dismissal the user did not ask for directly. A pinned panel ignores it,
    /// which is the whole point of the pin: switch away, look something up,
    /// come back to what you were typing.
    private func autoDismiss() {
        guard !isPinned else { return }
        reset()
    }
}
