import SwiftUI

/// The Filters window: a list of saved filters and the editor for the selected
/// one.
struct FiltersSettingsView: View {
    let store: FilterStore
    let service: RemindersService

    @State private var selection: UUID?
    @State private var allTasks: [TaskItem] = []
    @State private var query = ReminderQuery()
    @State private var isLoading = true

    private var selected: TaskFilter? {
        store.filters.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 280)

            Group {
                if let selected {
                    FilterEditorView(
                        filter: binding(for: selected),
                        lists: service.lists,
                        allTasks: allTasks
                    )
                } else {
                    ContentUnavailableView(
                        "No Filter Selected",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Pick a filter on the left, or add one.")
                    )
                }
            }
            .frame(minWidth: 470)
        }
        .frame(minWidth: 860, minHeight: 580)
        .task {
            store.seedIfEmpty()
            if selection == nil { selection = store.filters.first?.id }
            await refreshTasks()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.filters) { filter in
                    row(filter).tag(filter.id)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 2) {
                Button {
                    let new = TaskFilter()
                    store.add(new)
                    selection = new.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("New filter")

                Button {
                    guard let selected else { return }
                    store.duplicate(selected)
                    selection = store.filters.last?.id
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(selected == nil)
                .help("Duplicate filter")

                Button {
                    guard let selected else { return }
                    let index = store.filters.firstIndex { $0.id == selected.id }
                    store.remove(selected)
                    // Land on the neighbour rather than on nothing, so deleting
                    // several in a row does not need a click between each.
                    selection = index.flatMap { store.filters[safe: min($0, store.filters.count - 1)]?.id }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selected == nil)
                .help("Delete filter")

                Spacer()

                Button {
                    Task { await refreshTasks() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Reload reminders")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    private func row(_ filter: TaskFilter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: filter.symbolName)
                .foregroundStyle(filter.tint.color)
                .frame(width: 18)
            Text(filter.name).lineLimit(1)
            Spacer(minLength: 4)
            if !isLoading {
                Text("\(FilterEvaluator.evaluate(filter, against: allTasks).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    /// Writes straight through to the store, which persists and reloads the
    /// widget timelines — so an edit here shows up on the desktop without a
    /// save button.
    private func binding(for filter: TaskFilter) -> Binding<TaskFilter> {
        Binding(
            get: { store.filters.first { $0.id == filter.id } ?? filter },
            set: { store.update($0) }
        )
    }

    private func refreshTasks() async {
        isLoading = true
        defer { isLoading = false }
        if !query.hasAccess { _ = await query.requestAccess() }
        // Completed reminders are fetched unconditionally here so that toggling
        // "include completed" updates the preview without a manual reload.
        allTasks = await query.fetchTasks(includeCompleted: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
