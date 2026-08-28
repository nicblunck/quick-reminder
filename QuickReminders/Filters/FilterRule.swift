import Foundation

// MARK: - Fields

/// What a single rule looks at. Deliberately only fields EventKit actually
/// exposes — tags, flags and attachments have no API, so they are absent rather
/// than silently always-false.
enum FilterField: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case dueDate
    case startDate
    case list
    case priority
    case title
    case notes
    case completion
    case repeating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dueDate: "Due date"
        case .startDate: "Start date"
        case .list: "List"
        case .priority: "Priority"
        case .title: "Title"
        case .notes: "Notes"
        case .completion: "Completion"
        case .repeating: "Repeat"
        }
    }

    var symbolName: String {
        switch self {
        case .dueDate: "calendar"
        case .startDate: "calendar.badge.clock"
        case .list: "list.bullet"
        case .priority: "exclamationmark"
        case .title: "textformat"
        case .notes: "note.text"
        case .completion: "checkmark.circle"
        case .repeating: "repeat"
        }
    }

    /// The comparators offered for this field, in menu order.
    var comparators: [FilterComparator] {
        switch self {
        case .dueDate, .startDate:
            [.onDay, .onOrAfter, .onOrBefore, .isOverdue, .exists, .doesNotExist, .hasClockTime]
        case .list:
            [.isAnyOf, .isNoneOf]
        case .priority:
            [.equals, .isAtLeast, .isAtMost]
        case .title, .notes:
            [.contains, .doesNotContain, .beginsWith, .exists, .doesNotExist]
        case .completion, .repeating:
            [.isTrue, .isFalse]
        }
    }
}

// MARK: - Comparators

enum FilterComparator: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Falls exactly on the day `days` from today (0 = today, -1 = yesterday).
    case onDay
    /// Falls on or after the start of the day `days` from today.
    case onOrAfter
    /// Falls on or before the end of the day `days` from today.
    case onOrBefore
    /// Dated, and that moment is already past.
    case isOverdue
    /// Carries a clock time rather than being day-only.
    case hasClockTime
    case exists
    case doesNotExist
    case isAnyOf
    case isNoneOf
    case equals
    case isAtLeast
    case isAtMost
    case contains
    case doesNotContain
    case beginsWith
    case isTrue
    case isFalse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDay: "is on"
        case .onOrAfter: "is on or after"
        case .onOrBefore: "is on or before"
        case .isOverdue: "is overdue"
        case .hasClockTime: "has a time of day"
        case .exists: "is set"
        case .doesNotExist: "is not set"
        case .isAnyOf: "is any of"
        case .isNoneOf: "is none of"
        case .equals: "is"
        case .isAtLeast: "is at least"
        case .isAtMost: "is at most"
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .beginsWith: "begins with"
        case .isTrue: "is yes"
        case .isFalse: "is no"
        }
    }

    /// Which editor the rule row shows to the right of the comparator.
    var valueKind: FilterValueKind {
        switch self {
        case .onDay, .onOrAfter, .onOrBefore: .days
        case .isAnyOf, .isNoneOf: .lists
        case .equals, .isAtLeast, .isAtMost: .priority
        case .contains, .doesNotContain, .beginsWith: .text
        case .isOverdue, .hasClockTime, .exists, .doesNotExist, .isTrue, .isFalse: .none
        }
    }
}

enum FilterValueKind: Hashable, Sendable {
    case none
    case days
    case lists
    case priority
    case text
}

// MARK: - Values

/// A rule's right-hand side. One case per `FilterValueKind`, so an editor can
/// never leave a rule holding a value the comparator cannot read.
enum FilterValue: Codable, Hashable, Sendable {
    case none
    /// Day offset from today. 0 is today, 1 tomorrow, -1 yesterday.
    case days(Int)
    /// `EKCalendar.calendarIdentifier`s.
    case lists([String])
    case priority(ReminderPriority)
    case text(String)

    var kind: FilterValueKind {
        switch self {
        case .none: .none
        case .days: .days
        case .lists: .lists
        case .priority: .priority
        case .text: .text
        }
    }

    /// The empty value of a given kind, for when a comparator change makes the
    /// current one unreadable.
    static func placeholder(for kind: FilterValueKind) -> FilterValue {
        switch kind {
        case .none: .none
        case .days: .days(0)
        case .lists: .lists([])
        case .priority: .priority(.high)
        case .text: .text("")
        }
    }

    var days: Int? { if case .days(let d) = self { d } else { nil } }
    var lists: [String]? { if case .lists(let l) = self { l } else { nil } }
    var priority: ReminderPriority? { if case .priority(let p) = self { p } else { nil } }
    var text: String? { if case .text(let t) = self { t } else { nil } }
}

// MARK: - Rule

struct FilterRule: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var field: FilterField = .dueDate
    var comparator: FilterComparator = .onDay
    var value: FilterValue = .days(0)

    /// Re-points the rule at a new field, keeping the comparator if the new
    /// field still offers it and resetting the value when its kind changes.
    mutating func setField(_ newField: FilterField) {
        field = newField
        if !newField.comparators.contains(comparator) {
            comparator = newField.comparators[0]
        }
        alignValue()
    }

    mutating func setComparator(_ newComparator: FilterComparator) {
        comparator = newComparator
        alignValue()
    }

    private mutating func alignValue() {
        let kind = comparator.valueKind
        if value.kind != kind { value = .placeholder(for: kind) }
    }
}

// MARK: - Tree

enum FilterCombinator: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case all
    case any
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "all"
        case .any: "any"
        case .none: "none"
        }
    }

    /// Reads as "Match all of the following".
    var sentence: String {
        switch self {
        case .all: "Match all of the following"
        case .any: "Match any of the following"
        case .none: "Match none of the following"
        }
    }
}

/// A node is either a leaf rule or a nested group, which is what makes arbitrary
/// AND/OR nesting possible. `indirect` because a group contains nodes.
indirect enum FilterNode: Codable, Hashable, Sendable, Identifiable {
    case rule(FilterRule)
    case group(FilterGroup)

    var id: UUID {
        switch self {
        case .rule(let r): r.id
        case .group(let g): g.id
        }
    }
}

struct FilterGroup: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var combinator: FilterCombinator = .all
    var children: [FilterNode] = []

    static func all(_ children: [FilterNode]) -> FilterGroup {
        FilterGroup(combinator: .all, children: children)
    }

    static func any(_ children: [FilterNode]) -> FilterGroup {
        FilterGroup(combinator: .any, children: children)
    }
}

extension FilterNode {
    static func rule(
        _ field: FilterField, _ comparator: FilterComparator, _ value: FilterValue = .none
    ) -> FilterNode {
        .rule(FilterRule(field: field, comparator: comparator, value: value))
    }
}
