// AmpModel.swift: per-model data (names, Bonjour aliases, input tables).
//
// Purpose: one table of models. A new model is one entry in `AmpModel.all`, no new code path.
// Context: sources are Hegel "IP Control Codes" (H95/H120/H190/H390/H590, 2024-04-30) and the H590 sheet (2018-11-12).
// Dependencies: none.

public struct AmpInput: Sendable, Equatable, Hashable {
    public let number: Int
    public let name: String

    public init(_ number: Int, _ name: String) {
        self.number = number
        self.name = name
    }
}

public struct AmpModel: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    /// Upper-case, diacritic-free tokens that identify this model in a Bonjour service name.
    public let aliases: [String]
    /// Empty when the input table is unknown.
    public let inputs: [AmpInput]

    public init(id: String, displayName: String, aliases: [String], inputs: [AmpInput]) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.inputs = inputs
    }

    public func inputName(_ number: Int) -> String? {
        inputs.first { $0.number == number }?.name
    }

    public func inputNumber(named name: String) -> Int? {
        inputs.first { $0.name.lowercased() == name.lowercased() }?.number
    }

    public static func model(id: String) -> AmpModel? {
        all.first { $0.id == id.lowercased() }
    }

    /// Builds an input table from names listed in input-number order, starting at 1.
    private static func table(_ names: [String]) -> [AmpInput] {
        names.enumerated().map { AmpInput($0.offset + 1, $0.element) }
    }

    // NOTE (H590): the 2018 sheet says inputs 1-12 and the manual lists 3 RCA inputs. The 2024 sheet
    // lists 11 and omits Analog 3, likely an error. This mapping is inferred.
    public static let h590 = AmpModel(
        id: "h590", displayName: "H590", aliases: ["H590"],
        inputs: table(["XLR 1", "XLR 2", "Analog 1", "Analog 2", "Analog 3", "BNC", "Coaxial",
                       "Optical 1", "Optical 2", "Optical 3", "USB", "Network"]))

    public static let h390 = AmpModel(
        id: "h390", displayName: "H390", aliases: ["H390"],
        inputs: table(["XLR", "Analog 1", "Analog 2", "BNC", "Coaxial",
                       "Optical 1", "Optical 2", "Optical 3", "USB", "Network"]))

    private static let h190Inputs = table(["Balanced", "Analog 1", "Analog 2", "Coaxial",
                                           "Optical 1", "Optical 2", "Optical 3", "USB", "Network"])

    // H190V is matched by the H190 alias (alias match ignores a trailing letter).
    public static let h190 = AmpModel(id: "h190", displayName: "H190", aliases: ["H190"], inputs: h190Inputs)

    public static let h120 = AmpModel(id: "h120", displayName: "H120", aliases: ["H120"], inputs: h190Inputs)

    public static let h95 = AmpModel(
        id: "h95", displayName: "H95", aliases: ["H95"],
        inputs: table(["Analog 1", "Analog 2", "Coaxial", "Optical 1", "Optical 2", "Optical 3", "USB", "Network"]))

    /// Röst: no published input table in our sources, so inputs stay empty (numbers only).
    public static let rost = AmpModel(id: "rost", displayName: "Röst", aliases: ["ROST"], inputs: [])

    /// The model table. Add a model here and discovery, input naming and the CLI pick it up.
    public static let all: [AmpModel] = [h590, h390, h190, h120, h95, rost]
}
