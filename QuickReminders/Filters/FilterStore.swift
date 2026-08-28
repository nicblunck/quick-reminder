import Foundation
import Observation

/// The app-side, observable view of the stored filters.
///
/// Every mutation writes through immediately and then asks whoever owns
/// publishing to re-evaluate, so editing a filter updates the desktop without
/// the user doing anything else.
@MainActor
@Observable
final class FilterStore {

    private(set) var filters: [TaskFilter]

    /// Set by whoever owns the snapshot publisher. Filters changing means the
    /// widget's cached matches are wrong, not merely out of date.
    @ObservationIgnored
    var onChange: (() -> Void)?

    init() {
        filters = FilterStorage.load()
    }

    /// Called once access is settled, so the Filters tab and the widget gallery
    /// are never an empty page on a first run.
    func seedIfEmpty() {
        guard filters.isEmpty else { return }
        filters = TaskFilter.defaults()
        persist()
    }

    func add(_ filter: TaskFilter) {
        filters.append(filter)
        persist()
    }

    func update(_ filter: TaskFilter) {
        guard let index = filters.firstIndex(where: { $0.id == filter.id }) else { return }
        filters[index] = filter
        persist()
    }

    func remove(_ filter: TaskFilter) {
        filters.removeAll { $0.id == filter.id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        filters.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func duplicate(_ filter: TaskFilter) {
        var copy = filter
        copy.id = UUID()
        copy.name = "\(filter.name) Copy"
        // Rules carry their own identity too; leaving them shared would make the
        // editor's selection jump between the original and the copy.
        copy.root = Self.reidentified(filter.root)
        filters.append(copy)
        persist()
    }

    private static func reidentified(_ group: FilterGroup) -> FilterGroup {
        var fresh = group
        fresh.id = UUID()
        fresh.children = group.children.map { node in
            switch node {
            case .rule(var rule):
                rule.id = UUID()
                return .rule(rule)
            case .group(let child):
                return .group(reidentified(child))
            }
        }
        return fresh
    }

    private func persist() {
        FilterStorage.save(filters)
        onChange?()
    }
}
