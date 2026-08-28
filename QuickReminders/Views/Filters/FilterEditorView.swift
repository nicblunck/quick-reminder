import SwiftUI

/// Everything about one filter: how it looks, what it matches, and — live, as
/// you type — which of your reminders come back.
struct FilterEditorView: View {
    @Binding var filter: TaskFilter
    let lists: [ReminderList]
    /// Every reminder in the database, fetched once by the parent. The preview
    /// re-evaluates against this in memory, so editing a rule does not cost an
    /// EventKit round trip per keystroke.
    let allTasks: [TaskItem]

    private var matches: [TaskItem] {
        FilterEvaluator.evaluate(filter, against: allTasks)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    // A preview, not a button. The grid below is always on
                    // screen, so there is nothing to open — and nothing to fail
                    // to open.
                    Image(systemName: filter.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(filter.tint.color)
                        .frame(width: 34, height: 30)
                        .background(filter.tint.color.opacity(0.14), in: .rect(cornerRadius: 7))

                    TextField("Filter name", text: $filter.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        // Without this, Form pulls the placeholder out as a
                        // row label and right-aligns the field beside it.
                        .labelsHidden()
                }

                TintPickerView(tint: $filter.tint)
                    .padding(.vertical, 2)

                SymbolPickerView(symbolName: $filter.symbolName, tint: filter.tint.color)
            }

            Section("Conditions") {
                ConditionGroupView(group: $filter.root, lists: lists)
                    .padding(.vertical, 2)

                if filter.isEmpty {
                    Label(
                        "With no conditions this filter matches every reminder.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Display") {
                Picker("Sort by:", selection: $filter.sort) {
                    ForEach(FilterSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                // 0 is "no cap"; a stepper alone cannot say that, so the value
                // is spelled out beside it.
                LabeledContent("Limit to:") {
                    HStack(spacing: 6) {
                        Stepper(value: $filter.maxCount, in: 0...200) {
                            Text(filter.maxCount == 0 ? "No limit" : "^[\(filter.maxCount) reminder](inflect: true)")
                        }
                    }
                }

                Toggle("Include completed reminders", isOn: $filter.includeCompleted)
                Toggle("Show the add button on widgets", isOn: $filter.showsAddButton)
            }

            Section("Preview") {
                if matches.isEmpty {
                    Label("No reminders match right now.", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    LabeledContent("Matching now") {
                        Text("^[\(matches.count) reminder](inflect: true)")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(matches.prefix(6)) { item in
                            HStack(spacing: 7) {
                                Image(systemName: "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.indigo)
                                Text(item.title).lineLimit(1)
                                Spacer(minLength: 8)
                                if let due = DueDateFormat.label(for: item) {
                                    Text(due)
                                        .foregroundStyle(DueDateFormat.isOverdue(item) ? .red : .secondary)
                                }
                                Text(item.listTitle)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .font(.callout)
                        }
                        if matches.count > 6 {
                            Text("and \(matches.count - 6) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
