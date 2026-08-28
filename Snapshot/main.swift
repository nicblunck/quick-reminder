import WidgetKit
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

// MARK: - Widgets

/// The widget views, rendered at the three macOS widget point sizes.
///
/// `containerBackground(for: .widget)` is inert outside a real widget host, so
/// the card's fill and corner radius are drawn here instead — otherwise every
/// snapshot would come back on a transparent ground.
@MainActor
func widgetSnapshot(_ entry: FilterEntry, family: WidgetFamily, named name: String) {
    let size: CGSize = switch family {
    case .systemSmall: CGSize(width: 170, height: 170)
    case .systemLarge: CGSize(width: 364, height: 382)
    default: CGSize(width: 364, height: 170)
    }

    // No padding added here: the widget owns its own margins, and adding any
    // would mean these snapshots flattered a layout the real widget does not have.
    let card = FilterWidgetView(entry: entry, familyOverride: family)
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 22))
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))

    snapshot(card, named: name, width: size.width + 20)
}

MainActor.assumeIsolated {
    let today = TaskFilter(
        name: "Work Today", symbolName: "sun.max.fill", tint: .yellow,
        root: .all([.rule(.dueDate, .onOrBefore, .days(0))])
    )
    let later = TaskFilter(
        name: "Later", symbolName: "tray.full", tint: .purple,
        root: .any([.rule(.dueDate, .onOrAfter, .days(8)), .rule(.dueDate, .doesNotExist)])
    )

    func at(_ hour: Int, day: Int = 0) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: day, to: Date())!
        return Calendar.current.date(bySettingHour: hour, minute: 45, second: 0, of: base)!
    }

    func task(_ id: String, _ title: String, due: Date?, hasTime: Bool = true, repeating: Bool = false) -> TaskItem {
        TaskItem(
            id: id, title: title, notes: nil, isCompleted: false, priority: .none,
            dueDate: due, hasTime: hasTime, startDate: nil, isRepeating: repeating,
            listID: "work", listTitle: "Work", listColor: nil
        )
    }

    let rows = [
        task("1", "Book Hours", due: at(17), repeating: true),
        task("2", "Check on Groceries for the weekend", due: at(9), hasTime: false, repeating: true),
        task("3", "Review the Q3 deck before standup", due: at(11)),
        task("4", "Reply to the vendor thread", due: at(8, day: -1)),
        task("5", "Renew the domain", due: nil),
        task("6", "Draft the offsite agenda", due: at(14, day: 3)),
    ]

    func entry(_ filter: TaskFilter, _ items: [TaskItem], add: Bool = true) -> FilterEntry {
        FilterEntry(date: Date(), filter: filter, items: items, status: .ok, showsAddButton: add)
    }

    widgetSnapshot(entry(today, Array(rows.prefix(2))), family: .systemSmall, named: "widget-small")
    widgetSnapshot(entry(today, Array(rows.prefix(1))), family: .systemMedium, named: "widget-medium-one")
    widgetSnapshot(entry(today, rows), family: .systemMedium, named: "widget-medium-full")
    widgetSnapshot(entry(later, rows), family: .systemLarge, named: "widget-large")
    widgetSnapshot(entry(today, []), family: .systemMedium, named: "widget-empty")
    widgetSnapshot(entry(today, []), family: .systemSmall, named: "widget-empty-small")
    widgetSnapshot(entry(later, []), family: .systemLarge, named: "widget-empty-large")
    widgetSnapshot(
        FilterEntry(date: Date(), filter: today, items: [], status: .awaitingApp, showsAddButton: false),
        family: .systemMedium, named: "widget-awaiting-app"
    )
    widgetSnapshot(
        FilterEntry(
            date: Date(), filter: today, items: Array(rows.prefix(3)),
            status: .stale(since: Date().addingTimeInterval(-60 * 60 * 9)), showsAddButton: true
        ),
        family: .systemMedium, named: "widget-stale"
    )
    widgetSnapshot(entry(today, Array(rows.prefix(3)), add: false), family: .systemSmall, named: "widget-small-no-add")
}

// MARK: - Filter editor

MainActor.assumeIsolated {
    // The nested case: work lists, and (overdue OR high priority) — the shape
    // the whole AND/OR builder exists for.
    var nested = TaskFilter(
        name: "Work — Needs Attention", symbolName: "exclamationmark.triangle.fill", tint: .orange,
        root: .all([
            .rule(.list, .isAnyOf, .lists(["2"])),
            .group(.any([
                .rule(.dueDate, .isOverdue),
                .rule(.priority, .isAtLeast, .priority(.high)),
            ])),
        ])
    )
    let tasks = [
        TaskItem(
            id: "a", title: "Reply to the vendor thread", notes: nil, isCompleted: false,
            priority: .none, dueDate: Date().addingTimeInterval(-86_400), hasTime: true,
            startDate: nil, isRepeating: false,
            listID: "2", listTitle: "Work", listColor: nil
        ),
        TaskItem(
            id: "b", title: "Sign the renewal", notes: nil, isCompleted: false,
            priority: .high, dueDate: Date().addingTimeInterval(86_400 * 9), hasTime: false,
            startDate: nil, isRepeating: false,
            listID: "2", listTitle: "Work", listColor: nil
        ),
    ]

    snapshot(
        FilterEditorView(
            filter: Binding(get: { nested }, set: { nested = $0 }),
            lists: sampleLists,
            allTasks: tasks
        )
        .frame(width: 520, height: 700),
        named: "filter-editor",
        width: 520
    )
}

MainActor.assumeIsolated {
    // The day-offset editor, which only appears on relative date comparators.
    var later = TaskFilter(
        name: "Later", symbolName: "tray.full", tint: .purple,
        root: .any([
            .rule(.dueDate, .onOrAfter, .days(8)),
            .rule(.dueDate, .doesNotExist),
        ]),
        sort: .dueDateAscending
    )
    snapshot(
        FilterEditorView(
            filter: Binding(get: { later }, set: { later = $0 }),
            lists: sampleLists,
            allTasks: []
        )
        .frame(width: 560, height: 430),
        named: "filter-editor-days",
        width: 560
    )
}

MainActor.assumeIsolated {
    var symbol = "sun.max.fill"
    snapshot(
        SymbolPickerView(symbolName: Binding(get: { symbol }, set: { symbol = $0 }), tint: .orange)
            .padding(12)
            .frame(width: 380),
        named: "symbol-picker",
        width: 380
    )
}
