import SwiftUI

/// One level of the condition tree, drawn recursively.
///
/// Bindings into the children are looked up by `id` rather than by index: rows
/// are added and removed while their editors are on screen, and an index
/// captured a frame earlier can easily point at the wrong node — or past the
/// end of the array.
struct ConditionGroupView: View {
    @Binding var group: FilterGroup
    let lists: [ReminderList]
    /// Nil for the root group, which cannot be removed.
    var onDelete: (() -> Void)?
    var depth: Int = 0

    /// Nesting past this reads as noise and almost never means anything a
    /// flatter tree could not express.
    private static let maxDepth = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.children) { node in
                    row(for: node)
                }
                footer
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                // The spine that makes nesting legible at a glance.
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
            }
        }
        .padding(8)
        .background(depth == 0 ? Color.clear : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 7))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Match")
                .font(.callout)

            Picker("", selection: $group.combinator) {
                ForEach(FilterCombinator.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()

            Text("of the following")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Remove this group")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for node: FilterNode) -> some View {
        switch node {
        case .rule:
            RuleRowView(
                rule: ruleBinding(node),
                lists: lists,
                onDelete: { remove(node) }
            )
        case .group:
            ConditionGroupView(
                group: groupBinding(node),
                lists: lists,
                onDelete: { remove(node) },
                depth: depth + 1
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                group.children.append(.rule(FilterRule()))
            } label: {
                Label("Condition", systemImage: "plus")
            }

            if depth < Self.maxDepth {
                Button {
                    // A nested group defaults to the *opposite* combinator: the
                    // reason to nest at all is almost always to mix and with or.
                    let inner: FilterCombinator = group.combinator == .all ? .any : .all
                    group.children.append(.group(FilterGroup(combinator: inner, children: [.rule(FilterRule())])))
                } label: {
                    Label("Group", systemImage: "plus.rectangle.on.rectangle")
                }
            }

            Spacer()
        }
        .buttonStyle(.link)
        .font(.callout)
        .padding(.top, 1)
    }

    // MARK: - Mutation

    private func remove(_ node: FilterNode) {
        group.children.removeAll { $0.id == node.id }
    }

    private func ruleBinding(_ node: FilterNode) -> Binding<FilterRule> {
        Binding(
            get: {
                if case .rule(let rule)? = group.children.first(where: { $0.id == node.id }) {
                    return rule
                }
                if case .rule(let rule) = node { return rule }
                return FilterRule()
            },
            set: { newValue in
                guard let index = group.children.firstIndex(where: { $0.id == node.id }) else { return }
                group.children[index] = .rule(newValue)
            }
        )
    }

    private func groupBinding(_ node: FilterNode) -> Binding<FilterGroup> {
        Binding(
            get: {
                if case .group(let child)? = group.children.first(where: { $0.id == node.id }) {
                    return child
                }
                if case .group(let child) = node { return child }
                return FilterGroup()
            },
            set: { newValue in
                guard let index = group.children.firstIndex(where: { $0.id == node.id }) else { return }
                group.children[index] = .group(newValue)
            }
        )
    }
}

// MARK: - Rule row

struct RuleRowView: View {
    @Binding var rule: FilterRule
    let lists: [ReminderList]
    let onDelete: () -> Void

    /// Lists get a checklist under the row rather than an editor inside it —
    /// picking several things is a poor fit for a control that hides them.
    private var showsListChecklist: Bool { rule.comparator.valueKind == .lists }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            controls
            if showsListChecklist {
                ListChecklist(
                    selection: Binding(
                        get: { Set(rule.value.lists ?? []) },
                        set: { rule.value = .lists(Array($0)) }
                    ),
                    lists: lists
                )
                .padding(.leading, 2)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { rule.field },
                // Routed through `setField` so the comparator and value stay
                // consistent with the new field instead of being left stale.
                set: { rule.setField($0) }
            )) {
                ForEach(FilterField.allCases) { field in
                    Label(field.label, systemImage: field.symbolName).tag(field)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("", selection: Binding(
                get: { rule.comparator },
                set: { rule.setComparator($0) }
            )) {
                ForEach(rule.field.comparators) { comparator in
                    Text(comparator.label).tag(comparator)
                }
            }
            .labelsHidden()
            .fixedSize()

            valueEditor

            Spacer(minLength: 0)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove this condition")
        }
    }

    // MARK: - Value editors

    @ViewBuilder
    private var valueEditor: some View {
        switch rule.comparator.valueKind {
        case .none:
            EmptyView()
        case .days:
            DayOffsetField(days: Binding(
                get: { rule.value.days ?? 0 },
                set: { rule.value = .days($0) }
            ))
        case .lists:
            // Drawn beneath the row instead; see `showsListChecklist`.
            EmptyView()
        case .priority:
            Picker("", selection: Binding(
                get: { rule.value.priority ?? .high },
                set: { rule.value = .priority($0) }
            )) {
                ForEach(ReminderPriority.allCases, id: \.self) { priority in
                    Text(priority.label).tag(priority)
                }
            }
            .labelsHidden()
            .fixedSize()
        case .text:
            TextField("text", text: Binding(
                get: { rule.value.text ?? "" },
                set: { rule.value = .text($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
        }
    }
}

// MARK: - Day offset

/// A relative day, with the absolute meaning spelled out beside it.
///
/// "7" on its own is ambiguous — the caption is what tells you the rule means
/// next Wednesday and not "within 7 days".
private struct DayOffsetField: View {
    @Binding var days: Int

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $days, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 46)
                .multilineTextAlignment(.trailing)

            Stepper("", value: $days, in: -3650...3650)
                .labelsHidden()

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // The resolved meaning is the whole point of the caption, so it
                // keeps its width rather than truncating to "days — in 8…".
                .fixedSize()
        }
    }

    /// Spells out what the offset resolves to. "8" alone is ambiguous — it could
    /// as easily read as "within 8 days" as "on day 8".
    private var caption: String {
        switch days {
        case 0: "days — today"
        case 1: "days — tomorrow"
        case -1: "days — yesterday"
        case let d where d > 1: "days — in \(d) days"
        default: "days — \(-days) days ago"
        }
    }
}

// MARK: - List checklist

/// The lists a rule applies to, as checkboxes you can see all at once.
///
/// Deliberately not a menu: the whole question is "which of my lists count as
/// work", and a control that hides the options until clicked makes that harder
/// to answer and harder to check afterwards.
private struct ListChecklist: View {
    @Binding var selection: Set<String>
    let lists: [ReminderList]

    private let columns = [GridItem(.adaptive(minimum: 150), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if lists.isEmpty {
                Text("No lists loaded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                    ForEach(lists) { list in
                        Toggle(isOn: binding(for: list)) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(list.color?.color ?? .secondary)
                                    .frame(width: 8, height: 8)
                                Text(list.title)
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                footer
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if selection.isEmpty {
                // The one piece of behaviour nobody guesses: an empty selection
                // is "no restriction", not "match nothing".
                Label("Nothing ticked, so every list counts.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("^[\(selection.count) list](inflect: true) ticked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear") { selection.removeAll() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
    }

    private func binding(for list: ReminderList) -> Binding<Bool> {
        Binding(
            get: { selection.contains(list.id) },
            set: { isOn in
                if isOn { selection.insert(list.id) } else { selection.remove(list.id) }
            }
        )
    }
}
