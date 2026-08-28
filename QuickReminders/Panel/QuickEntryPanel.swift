import AppKit
import SwiftUI

/// The floating capture window.
///
/// The shape has exactly one owner: the corner radius on the glass backdrop.
/// Nothing rounds anything in SwiftUI; a rounded card drawn inside an
/// already-rounded window leaves a seam wherever the two curves disagree.
///
/// The shadow is drawn by `PanelCardView`, not by AppKit. AppKit's window shadow
/// is derived from the window's backing alpha, and for a material composited by
/// the window server that alpha reads as the full rectangle — so the shadow comes
/// out square and shows through the card's corner notches as four hard corners.
/// `NSVisualEffectView` had `maskImage` to tell the server the real shape;
/// `NSGlassEffectView` has no equivalent, so the shadow has to be ours.
///
/// `.nonactivatingPanel` keeps the app underneath from being disturbed, but such a
/// panel refuses key status by default, which would leave the text field unable to
/// accept typing. Hence `canBecomeKey`.
final class QuickEntryPanel: NSPanel {

    /// Deliberately well past the system window radius. A capture panel this
    /// small reads as a card rather than a document window, and the softer
    /// corner is what makes it read that way.
    static let cornerRadius: CGFloat = 22

    /// Transparent room around the card for the drop shadow to fall into.
    /// Must comfortably exceed the shadow's blur plus its offset, or the shadow
    /// is clipped by the window edge and ends in a straight line.
    static let cardInset: CGFloat = 34


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
        // Off deliberately — see the note on the class. `PanelCardView` draws a
        // shadow shaped to the actual card instead.
        hasShadow = false

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

/// The panel's content view: the glass card floating inside a transparent margin,
/// with the card's drop shadow drawn underneath it.
///
/// The shadow lives here rather than on the window because AppKit shapes a window
/// shadow from the backing alpha, which a window-server-composited material
/// reports as the whole rectangle. A `shadowPath` states the shape outright, so
/// there is nothing left to infer and nothing to come out square.
final class PanelCardView: NSView {

    let card: NSGlassEffectView
    private let cardShadow = CALayer()

    init(card: NSGlassEffectView) {
        self.card = card
        super.init(frame: .zero)

        wantsLayer = true
        cardShadow.shadowColor = NSColor.black.cgColor
        cardShadow.shadowOpacity = 0.24
        cardShadow.shadowRadius = 16
        // Layer geometry here is bottom-left origin, so down is negative.
        cardShadow.shadowOffset = CGSize(width: 0, height: -7)
        layer?.addSublayer(cardShadow)

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let inset = QuickEntryPanel.cardInset
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            card.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The card changes height as notes and URL fields appear, so the shadow's
    /// shape is restated on every layout rather than set once.
    override func layout() {
        super.layout()
        cardShadow.frame = card.frame
        cardShadow.shadowPath = Path(
            roundedRect: CGRect(origin: .zero, size: card.frame.size),
            cornerRadius: QuickEntryPanel.cornerRadius,
            style: .continuous
        ).cgPath
    }

    /// The margin is window too, so without this the panel would swallow clicks
    /// in a region that looks like empty desktop.
    override func hitTest(_ point: NSPoint) -> NSView? {
        card.frame.contains(point) ? super.hitTest(point) : nil
    }
}

