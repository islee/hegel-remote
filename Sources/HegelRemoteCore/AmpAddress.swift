// AmpAddress.swift: where the remembered amplifier is, and how the user named it.
//
// Purpose: the one value the app persists to find the amp again (manual entry or a discovery result).
// Context: `modelID` indexes `AmpModel.all`; H590 is assumed when unknown because it is the only model with
//   a live-verified input table. Pure Foundation.
// Dependencies: HegelProtocol (AmpModel).
import Foundation
import HegelProtocol

public struct AmpAddress: Hashable, Sendable, Codable {
    public var host: String
    public var port: UInt16
    public var modelID: String
    /// Optional user label ("Living room"); nil shows just the model.
    public var name: String?

    public static let defaultPort: UInt16 = 50001

    public init(host: String, port: UInt16 = AmpAddress.defaultPort, modelID: String = AmpModel.h590.id, name: String? = nil) {
        self.host = host
        self.port = port
        self.modelID = modelID
        self.name = name
    }

    public var model: AmpModel { AmpModel.model(id: modelID) ?? .h590 }

    /// "H590" or "H590 · Living room".
    public var title: String {
        if let name, !name.isEmpty { return "\(model.displayName) · \(name)" }
        return model.displayName
    }

    /// Parses what a user types in the manual field: `192.168.0.10`, `192.168.0.10:50002` or `amp.local`.
    /// Returns nil for an empty host or a bad port.
    public static func parse(_ text: String) -> AmpAddress? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // An IPv6 literal would contain several colons; only one colon means host:port.
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard let port = UInt16(parts[1]), port > 0, !parts[0].isEmpty else { return nil }
            return AmpAddress(host: String(parts[0]), port: port)
        }
        guard parts.count == 1 else { return nil }
        return AmpAddress(host: trimmed)
    }

    /// Host, with the port appended only when it is not the standard one.
    public var displayHost: String { port == Self.defaultPort ? host : "\(host):\(port)" }
}
