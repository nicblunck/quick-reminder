import AppIntents
import WidgetKit

/// One filter, as something the widget configuration sheet can list.
struct FilterEntity: AppEntity, Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbolName: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Filter"
    static let defaultQuery = FilterEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }

    init(_ filter: TaskFilter) {
        id = filter.id
        name = filter.name
        symbolName = filter.symbolName
    }
}

/// Backed by the shared App Group, so filters created in the app show up in the
/// widget configuration without the extension needing any state of its own.
struct FilterEntityQuery: EntityQuery {

    func entities(for identifiers: [UUID]) async throws -> [FilterEntity] {
        let byID = Dictionary(uniqueKeysWithValues: FilterStorage.load().map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(FilterEntity.init) }
    }

    func suggestedEntities() async throws -> [FilterEntity] {
        FilterStorage.load().map(FilterEntity.init)
    }

    /// What a freshly-dropped widget shows before the user picks anything.
    func defaultResult() async -> FilterEntity? {
        FilterStorage.load().first.map(FilterEntity.init)
    }
}

struct SelectFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Filter"
    static let description = IntentDescription(
        "Pick which of your saved filters this widget lists."
    )

    @Parameter(title: "Filter")
    var filter: FilterEntity?

    /// Per-widget override of the filter's own preference, so the same filter
    /// can carry an add button on one widget and not on another.
    @Parameter(title: "Show Add Button", default: true)
    var showsAddButton: Bool

    init() {}

    init(filter: FilterEntity?, showsAddButton: Bool = true) {
        self.filter = filter
        self.showsAddButton = showsAddButton
    }
}
