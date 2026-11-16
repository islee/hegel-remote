// Skin.swift: a skin is data. Colours, readout font and the volume-control type, Codable, with three built-ins.
//
// Purpose: let a user define a skin without code changes. A skin file is just the JSON of one `Skin`; the
//   built-ins are `Skin` values too, so the UI never special-cases them. Loading user files from disk is a
//   later stage; `SettingsStore.userSkins` already holds decoded user skins.
// Context: values come from the design canvas (Docs/design/canvas/Dial.dc.html). Pure Foundation, no SwiftUI:
//   the view layer converts `HexColor` to `Color` (Views/SkinStyle.swift).
// Dependencies: Foundation.
import Foundation

/// `#RRGGBB` or `#RRGGBBAA`, kept as components so views on any platform can build their colour type from it.
public struct HexColor: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`; nil for anything else.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// Built-in skins are written as literals; a bad literal is a programming error, hence the precondition.
    public init(stringLiteral value: String) {
        guard let c = HexColor(hex: value) else { preconditionFailure("bad colour literal \(value)") }
        self = c
    }

    public var hex: String {
        func byte(_ v: Double) -> String { String(format: "%02X", Int((min(1, max(0, v)) * 255).rounded())) }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? rgb + byte(alpha) : rgb
    }

    // Codable as the hex string, so a skin file reads `"accent": "#D9A441"`.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let c = HexColor(hex: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a hex colour: \(text)"))
        }
        self = c
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

/// Which font draws the dot-matrix readout. `.doto` is bundled (OFL); `.systemMonospaced` is the fallback.
public enum ReadoutFont: String, Codable, Sendable, CaseIterable {
    case doto
    case systemMonospaced
}

public enum VolumeControlKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case wheel
    case slider
    public var id: String { rawValue }
}

/// The palette. Names follow the design canvas so a skin author can map them 1:1.
public struct SkinColors: Hashable, Sendable, Codable {
    public var background: HexColor
    public var foreground: HexColor
    public var muted: HexColor
    public var line: HexColor
    public var button: HexColor
    public var accent: HexColor
    public var readoutBackground: HexColor
    public var readoutForeground: HexColor
    /// The dial ring is a radial gradient highlight -> mid -> shadow; a flat ring repeats one colour.
    public var ringHighlight: HexColor
    public var ringMid: HexColor
    public var ringShadow: HexColor
    public var shadow: HexColor
}

public struct Skin: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var colors: SkinColors
    public var readoutFont: ReadoutFont
    /// The skin's default control; the user can override it in settings.
    public var volumeControl: VolumeControlKind

    public init(id: String, name: String, colors: SkinColors, readoutFont: ReadoutFont = .doto,
                volumeControl: VolumeControlKind = .wheel) {
        self.id = id
        self.name = name
        self.colors = colors
        self.readoutFont = readoutFont
        self.volumeControl = volumeControl
    }

    /// A skin's visual tone, derived from its background; views use it for system controls (sheets, switches).
    public var isDark: Bool {
        let c = colors.background
        return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue < 0.5
    }

    // MARK: Built-ins (Docs/design/canvas/Dial.dc.html)

    public static let silver = Skin(
        id: "silver", name: "Silver",
        colors: SkinColors(
            background: "#e9eaeb", foreground: "#141516", muted: "#55595e", line: "#b4b7bb", button: "#f5f6f7",
            accent: "#141516", readoutBackground: "#111213", readoutForeground: "#f4f6f8",
            ringHighlight: "#ffffff", ringMid: "#d4d6d9", ringShadow: "#a9acb0", shadow: "#9ea2a6"))

    public static let black = Skin(
        id: "black", name: "Black",
        colors: SkinColors(
            background: "#0c0d0e", foreground: "#e8eaec", muted: "#959aa0", line: "#2f3337", button: "#16181a",
            accent: "#d9a441", readoutBackground: "#000000", readoutForeground: "#f4f6f8",
            ringHighlight: "#4a4e54", ringMid: "#2a2d31", ringShadow: "#16181a", shadow: "#000000"))

    public static let oled = Skin(
        id: "oled", name: "OLED",
        colors: SkinColors(
            background: "#000000", foreground: "#f4f6f8", muted: "#8a9096", line: "#26292c", button: "#000000",
            accent: "#f4f6f8", readoutBackground: "#000000", readoutForeground: "#f4f6f8",
            ringHighlight: "#0b0b0c", ringMid: "#0b0b0c", ringShadow: "#0b0b0c", shadow: "#000000"))

    public static let builtIns: [Skin] = [silver, black, oled]
    public static let defaultID = silver.id

    /// Decodes one skin file (JSON of a `Skin`). This is the whole "user skin" contract.
    public static func decode(json data: Data) throws -> Skin {
        try JSONDecoder().decode(Skin.self, from: data)
    }

    public func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
