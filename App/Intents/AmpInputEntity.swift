// AmpInputEntity.swift: the amp's enabled inputs as an App Entity, named as the user named them.
//
// Purpose: lets Siri and Shortcuts resolve "switch to Pontus" to input 1. Only enabled inputs are offered.
// Dependencies: AppIntents, Core (InputCatalog, SettingsStore).
import HegelRemoteCore
import AppIntents
import Foundation

struct AmpInputEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Amplifier input")
    static let defaultQuery = AmpInputQuery()

    /// The input number.
    let id: Int
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ item: InputItem) {
        id = item.number
        name = item.name
    }
}

struct AmpInputQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [AmpInputEntity] {
        let settings = SettingsStore.shared
        return identifiers.compactMap { settings.input(number: $0) }.map(AmpInputEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [AmpInputEntity] {
        let settings = SettingsStore.shared
        if let hit = InputCatalog.match(name: string, model: settings.model, settings: settings.inputSettings), hit.isEnabled {
            return [AmpInputEntity(hit)]
        }
        let q = InputCatalog.normalize(string)
        return settings.enabledInputs.filter { InputCatalog.normalize($0.name).contains(q) }.map(AmpInputEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AmpInputEntity] {
        SettingsStore.shared.enabledInputs.map(AmpInputEntity.init)
    }
}
