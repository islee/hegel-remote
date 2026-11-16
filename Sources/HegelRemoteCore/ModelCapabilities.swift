// ModelCapabilities.swift: per-model UI capability data. The views read this; they never branch on a model.
//
// Purpose: HegelKit's `AmpModel` holds the protocol-side table (names, aliases, inputs). This adds what the
//   app needs to lay out controls for a model: which controls exist, the volume range, support level and notes.
//   Adding H390/H190/H95/Röst support later is a change to this table, not to a view.
// Context: every Hegel IP-control sheet in our sources exposes the same five commands (p/i/v/m/r), so all
//   models get the same controls; only the H590 was verified against a live amp. The others are listed as
//   "untested" so the picker can show them, and the UI says so.
// Dependencies: HegelProtocol (AmpModel).
import Foundation
import HegelProtocol

public enum AmpControl: String, Sendable, Codable, CaseIterable {
    case power, volume, mute, input
}

public enum SupportLevel: String, Sendable, Codable {
    /// Verified against a real unit.
    case verified
    /// From the control sheet only; expected to work, never tried.
    case untested
}

public struct ModelCapabilities: Hashable, Sendable {
    public let modelID: String
    public let controls: Set<AmpControl>
    public let volumeRange: ClosedRange<Int>
    public let support: SupportLevel
    public let notes: String

    public func supports(_ control: AmpControl) -> Bool { controls.contains(control) }

    static let allControls: Set<AmpControl> = Set(AmpControl.allCases)

    /// The table. Order = the order the model picker shows.
    public static let all: [ModelCapabilities] = [
        ModelCapabilities(
            modelID: AmpModel.h590.id, controls: allControls, volumeRange: 0...100, support: .verified,
            notes: "Verified live (2026-11). Inputs 1-12; 12 = Network. Volume is 0-100 %; the amp may round when a max-volume limit is set."),
        ModelCapabilities(
            modelID: AmpModel.h390.id, controls: allControls, volumeRange: 0...100, support: .untested,
            notes: "Same IP commands per Hegel's sheet (2024). Inputs 1-10. Not tried on a real unit."),
        ModelCapabilities(
            modelID: AmpModel.h190.id, controls: allControls, volumeRange: 0...100, support: .untested,
            notes: "Same IP commands per Hegel's sheet (2024). Inputs 1-9 (H190V discovers as H190). Not tried on a real unit."),
        ModelCapabilities(
            modelID: AmpModel.h120.id, controls: allControls, volumeRange: 0...100, support: .untested,
            notes: "Same IP commands per Hegel's sheet (2024). Inputs 1-9. Not tried on a real unit."),
        ModelCapabilities(
            modelID: AmpModel.h95.id, controls: allControls, volumeRange: 0...100, support: .untested,
            notes: "Same IP commands per Hegel's sheet (2024). Inputs 1-8. Not tried on a real unit."),
        ModelCapabilities(
            modelID: AmpModel.rost.id, controls: allControls, volumeRange: 0...100, support: .untested,
            notes: "No input table in our sources: inputs show as numbers 1-12. Not tried on a real unit."),
    ]

    public static func capabilities(for modelID: String) -> ModelCapabilities {
        all.first { $0.modelID == modelID.lowercased() } ?? all[0]
    }

    public var model: AmpModel { AmpModel.model(id: modelID) ?? .h590 }

    /// Picker label: "H390 (untested)".
    public var pickerLabel: String {
        support == .verified ? model.displayName : "\(model.displayName) (untested)"
    }
}
