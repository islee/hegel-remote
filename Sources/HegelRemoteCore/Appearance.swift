// Appearance.swift: light/dark appearance setting, the light+dark skin pairing and the pure skin resolver.
//
// Purpose: the skin follows the system theme. The user picks an appearance (system / light / dark) and a
//   pairing (which skin to use in light, which in dark); `SkinResolver.resolve` turns those plus the current
//   system scheme into the one skin to draw.
// Context: pure logic, no SwiftUI; the apps feed `systemIsDark` from the SwiftUI `colorScheme` environment.
//   Any built-in or user skin can sit in either slot, so Silver in the dark slot is allowed.
// Dependencies: Foundation, Skin.
import Foundation

public enum AppearanceSetting: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Whether the dark slot applies: an explicit choice wins, `system` defers to the OS.
    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
}

/// Which skin to use in light and in dark, by skin id (ids, not values, so a user skin edit carries over).
public struct SkinPairing: Hashable, Codable, Sendable {
    public var lightID: String
    public var darkID: String

    public init(lightID: String, darkID: String) {
        self.lightID = lightID
        self.darkID = darkID
    }

    public static let `default` = SkinPairing(lightID: Skin.silver.id, darkID: Skin.black.id)

    /// Migration from the single-skin setting: the one skin the user picked serves both slots.
    public init(migratingSingle skinID: String) {
        self.init(lightID: skinID, darkID: skinID)
    }
}

public enum SkinResolver {
    /// `(appearanceSetting, systemIsDark, pairing) -> Skin`. `skins` is the catalogue the ids are looked up in; an
    /// id that no longer exists (a deleted user skin) falls back to Silver (light slot) or Black (dark slot).
    public static func resolve(
        appearance: AppearanceSetting, systemIsDark: Bool, pairing: SkinPairing, skins: [Skin] = Skin.builtIns
    ) -> Skin {
        if appearance.isDark(systemIsDark: systemIsDark) {
            return skins.first { $0.id == pairing.darkID } ?? .black
        }
        return skins.first { $0.id == pairing.lightID } ?? .silver
    }
}
