import Foundation

// MARK: - Tint

/// A filter's accent, as a fixed palette rather than a free colour well: these
/// have to survive `Codable` round-trips, read correctly in both light and dark
/// widget renderings, and be pickable in a menu.
enum FilterTint: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case blue, purple, indigo, teal, mint, green, yellow, orange, red, pink, brown, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .graphite: "Graphite"
        default: rawValue.capitalized
        }
    }
}

// MARK: - Sorting

enum FilterSort: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case dueDateAscending
    case dueDateDescending
    case priorityFirst
    case title
    case listThenDueDate
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dueDateAscending: "Due date, soonest first"
        case .dueDateDescending: "Due date, latest first"
        case .priorityFirst: "Priority, highest first"
        case .title: "Title, A–Z"
        case .listThenDueDate: "List, then due date"
        case .manual: "Reminders app order"
        }
    }
}

// MARK: - Filter

/// A named, coloured, user-defined query over the Reminders database.
///
/// The `root` group is what makes this "configurable" rather than a fixed set of
/// toggles — it nests arbitrarily, so "due more than a week out **or** undated"
/// is expressible without a special case.
struct TaskFilter: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String = "New Filter"
    /// An SF Symbol name. Validated against the system at edit time so a typo
    /// cannot leave a widget with a blank glyph.
    var symbolName: String = "line.3.horizontal.decrease.circle"
    var tint: FilterTint = .blue
    var root: FilterGroup = FilterGroup(combinator: .all, children: [])
    var sort: FilterSort = .dueDateAscending
    /// 0 means "as many as the widget size fits".
    var maxCount: Int = 0
    /// Completed reminders are hidden unless a rule explicitly asks for them.
    var includeCompleted: Bool = false
    /// The "+" button in the widget's bottom-right corner. Also exposed in the
    /// widget's own configuration, so one filter can show it on one widget and
    /// hide it on another.
    var showsAddButton: Bool = true

    var isEmpty: Bool { root.children.isEmpty }
}

// MARK: - Presets

extension TaskFilter {

    /// The starter set. Seeded on first launch so the Filters tab is never an
    /// empty page, and so the widget gallery has something to preview.
    ///
    /// `workListIDs` is empty until the user picks their work lists, which
    /// leaves the two work filters matching every list rather than nothing —
    /// an empty `isAnyOf` is treated as "unconstrained" by the evaluator.
    static func defaults(workListIDs: [String] = []) -> [TaskFilter] {
        [
            TaskFilter(
                name: "Work Today",
                symbolName: "sun.max.fill",
                tint: .yellow,
                root: .all([
                    .rule(.dueDate, .onOrBefore, .days(0)),
                    .rule(.list, .isAnyOf, .lists(workListIDs)),
                ]),
                sort: .dueDateAscending
            ),
            TaskFilter(
                name: "Work This Week",
                symbolName: "calendar",
                tint: .blue,
                root: .all([
                    .rule(.dueDate, .onOrAfter, .days(1)),
                    .rule(.dueDate, .onOrBefore, .days(7)),
                    .rule(.list, .isAnyOf, .lists(workListIDs)),
                ]),
                sort: .dueDateAscending
            ),
            TaskFilter(
                name: "Later",
                symbolName: "tray.full",
                tint: .purple,
                // The one that needs real nesting: due beyond the week, *or* no
                // deadline at all.
                root: .any([
                    .rule(.dueDate, .onOrAfter, .days(8)),
                    .rule(.dueDate, .doesNotExist),
                ]),
                sort: .dueDateAscending
            ),
        ]
    }
}
