import AppKit
import SwiftUI

// Renders views to PNG without ever showing a window. `.prohibited` guarantees
// no Dock icon, no activation, and nothing appearing over whatever the user is
// doing — UI can be checked while they keep working.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let outputDirectory = URL(fileURLWithPath: "/tmp/qr-snapshots")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

@MainActor
func snapshot(_ view: some View, named name: String, width: CGFloat = 700) {
    // NSHostingView (not SwiftUI's ImageRenderer) because Menu and other
    // AppKit-backed controls only draw their real chrome in a live view tree.
    // Offscreen views get no display link, so SwiftUI transitions never advance
    // and anything mid-animation would be captured at its start state (a chip
    // frozen at opacity 0, say). Disable animations so every snapshot shows the
    // settled result.
    let hosting = NSHostingView(
        rootView: AnyView(view.transaction { $0.disablesAnimations = true })
    )
    hosting.wantsLayer = true
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 600)
    hosting.layoutSubtreeIfNeeded()

    // Let `.task` work and the parse debounce settle, otherwise the snapshot
    // shows a half-initialised view and quietly lies about the layout.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    hosting.layoutSubtreeIfNeeded()

    let fitted = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: CGSize(
        width: max(fitted.width, 1), height: max(fitted.height, 1)
    ))
    hosting.layoutSubtreeIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("‼️  \(name): could not allocate a bitmap")
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("‼️  \(name): could not encode PNG")
        return
    }
    let url = outputDirectory.appendingPathComponent("\(name).png")
    try? data.write(to: url)
    print("✅  \(name)  \(Int(hosting.bounds.width))×\(Int(hosting.bounds.height))  →  \(url.path)")
}


let sampleLists = [
    ReminderList(id: "1", title: "Inbox", color: ListColor(red: 0.0, green: 0.48, blue: 1.0)),
    ReminderList(id: "2", title: "Work", color: ListColor(red: 1.0, green: 0.58, blue: 0.0)),
    ReminderList(id: "3", title: "Groceries", color: ListColor(red: 0.20, green: 0.78, blue: 0.35)),
]

MainActor.assumeIsolated {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "snapshot") ?? .standard)

    @MainActor func entry(_ text: String) -> some View {
        QuickEntryView(
            service: RemindersService.preview(lists: sampleLists),
            preferences: preferences,
            initialText: text,
            dismiss: {}
        )
        .background(Color(white: 0.30))
    }

    snapshot(entry(""), named: "entry-empty")
    snapshot(entry("Finish Roblox today by 18:00"), named: "entry-day-and-time")
    snapshot(entry("call dentist tomorrow !!!"), named: "entry-day-and-priority")
    snapshot(entry("submit tax return next month 9am !"), named: "entry-full")

    for (marks, name) in [("", "none"), ("!", "low"), ("!!", "medium"), ("!!!", "high")] {
        snapshot(entry("review the deck \(marks)"), named: "priority-\(name)")
    }

    snapshot(
        DatePopoverView(
            selection: .constant(Date()), hasDate: true, onClear: {}, onClose: {}
        )
        .background(Color(white: 0.96)),
        named: "date-popover",
        width: 460
    )

    snapshot(
        TimePopoverView(
            selection: .constant(TimeOfDay(hour: 18, minute: 0)), onClear: {}, onClose: {}
        )
        .background(Color(white: 0.96)),
        named: "time-popover",
        width: 320
    )

}
