// SettingsStore.swift: everything the app persists, as one observable object over UserDefaults.
//
// Purpose: a single source of truth for the remembered amp, skin choice, control choice, input settings,
//   custom buttons and user skins. Views bind to it; intents read it; tests give it an isolated suite.
// Context: free-account signing (no App Groups), so plain UserDefaults is enough: intents run inside the app
//   process. Scalars are stored under plain keys so launch arguments (`-lightSkinID silver`) override them, which
//   the screenshot script relies on; collections are JSON blobs.
// Dependencies: Foundation, HegelProtocol, the Core model types.
import Foundation
import HegelProtocol

@MainActor @Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    enum Key {
        static let ampHost = "ampHost", ampPort = "ampPort", ampModelID = "ampModelID", ampName = "ampName"
        // `skinID` is the pre-pairing single-skin key; it is only read, once, to migrate.
        static let skinID = "skinID", volumeControl = "volumeControl"
        static let appearance = "appearance", lightSkinID = "lightSkinID", darkSkinID = "darkSkinID"
        static let iconChoice = "iconChoice", suggestModelIcon = "suggestModelIcon"
        static let inputSettings = "inputSettings", customButtons = "customButtons", userSkins = "userSkins"
        static let plexClientID = "plexClientID"
    }

    private let defaults: UserDefaults

    public var ampAddress: AmpAddress? {
        didSet {
            defaults.set(ampAddress?.host, forKey: Key.ampHost)
            defaults.set(ampAddress.map { Int($0.port) }, forKey: Key.ampPort)
            defaults.set(ampAddress?.modelID, forKey: Key.ampModelID)
            defaults.set(ampAddress?.name, forKey: Key.ampName)
        }
    }

    public var appearance: AppearanceSetting {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    public var skinPairing: SkinPairing {
        didSet {
            defaults.set(skinPairing.lightID, forKey: Key.lightSkinID)
            defaults.set(skinPairing.darkID, forKey: Key.darkSkinID)
        }
    }

    /// The current system scheme, pushed in by the apps from the SwiftUI `colorScheme`. Not persisted.
    public var systemIsDark = false

    public var iconChoice: IconChoice {
        didSet { defaults.set(iconChoice.storageValue, forKey: Key.iconChoice) }
    }

    /// Offer the connected amp's icon in Settings when one exists (never applied without the user's tap).
    public var suggestModelIcon: Bool {
        didSet { defaults.set(suggestModelIcon, forKey: Key.suggestModelIcon) }
    }

    /// nil = use the skin's own default.
    public var volumeControlOverride: VolumeControlKind? {
        didSet { defaults.set(volumeControlOverride?.rawValue, forKey: Key.volumeControl) }
    }

    public var inputSettings: [InputSetting] {
        didSet { store(inputSettings, key: Key.inputSettings) }
    }

    public var customButtons: [CustomButton] {
        didSet { store(customButtons, key: Key.customButtons) }
    }

    public var userSkins: [Skin] {
        didSet { store(userSkins, key: Key.userSkins) }
    }

    /// Stable Plex Companion client identifier for this install.
    public let plexClientID: String

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let host = defaults.string(forKey: Key.ampHost), !host.isEmpty {
            let port = defaults.integer(forKey: Key.ampPort)
            ampAddress = AmpAddress(
                host: host,
                port: (1...65535).contains(port) ? UInt16(port) : AmpAddress.defaultPort,
                modelID: defaults.string(forKey: Key.ampModelID) ?? AmpModel.h590.id,
                name: defaults.string(forKey: Key.ampName))
        } else {
            ampAddress = nil
        }
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
        skinPairing = Self.loadPairing(from: defaults)
        iconChoice = IconChoice(storageValue: defaults.string(forKey: Key.iconChoice))
        suggestModelIcon = defaults.object(forKey: Key.suggestModelIcon) as? Bool ?? true
        volumeControlOverride = defaults.string(forKey: Key.volumeControl).flatMap(VolumeControlKind.init(rawValue:))
        inputSettings = Self.load([InputSetting].self, key: Key.inputSettings, from: defaults) ?? []
        // First launch ships one example preset; an emptied list stays empty (the key then holds `[]`).
        customButtons = Self.load([CustomButton].self, key: Key.customButtons, from: defaults) ?? [.exampleLateNight]
        userSkins = Self.load([Skin].self, key: Key.userSkins, from: defaults) ?? []
        if let id = defaults.string(forKey: Key.plexClientID) {
            plexClientID = id
        } else {
            plexClientID = "hegel-remote-" + UUID().uuidString.lowercased()
            defaults.set(plexClientID, forKey: Key.plexClientID)
        }
    }

    // MARK: Derived

    public var allSkins: [Skin] { Skin.builtIns + userSkins }

    /// The skin to draw now: appearance setting + system scheme + pairing.
    public var skin: Skin {
        SkinResolver.resolve(appearance: appearance, systemIsDark: systemIsDark, pairing: skinPairing, skins: allSkins)
    }

    /// The icon to apply: the stored choice, or the default when its artwork does not exist.
    public var effectiveIconChoice: IconChoice { AppIcons.effective(iconChoice) }

    /// The connected amp's icon, when suggestions are on and it is not already chosen.
    public var suggestedIcon: IconChoice? {
        AppIcons.suggestion(connectedModelID: ampAddress?.modelID, current: iconChoice, enabled: suggestModelIcon)
    }

    public var volumeControl: VolumeControlKind { volumeControlOverride ?? skin.volumeControl }

    public var model: AmpModel { ampAddress?.model ?? .h590 }

    public var capabilities: ModelCapabilities { ModelCapabilities.capabilities(for: model.id) }

    public var inputs: [InputItem] { InputCatalog.items(model: model, settings: inputSettings) }

    public var enabledInputs: [InputItem] { InputCatalog.enabledItems(model: model, settings: inputSettings) }

    public func input(number: Int) -> InputItem? { InputCatalog.item(number: number, model: model, settings: inputSettings) }

    public func inputName(_ number: Int) -> String? { input(number: number)?.name }

    public func update(_ setting: InputSetting) {
        inputSettings = InputCatalog.updating(inputSettings, with: setting)
    }

    /// Adds a user skin from its JSON. A skin whose id collides with an existing one replaces it.
    public func addUserSkin(json: Data) throws -> Skin {
        let skin = try Skin.decode(json: json)
        userSkins.removeAll { $0.id == skin.id }
        userSkins.append(skin)
        return skin
    }

    public func forgetAmp() {
        ampAddress = nil
    }

    // MARK: Storage helpers

    private func store<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// New keys win; otherwise the old single `skinID` (if the user ever picked one) serves both slots and is
    /// rewritten as the pair, so the legacy key is read exactly once.
    private static func loadPairing(from defaults: UserDefaults) -> SkinPairing {
        let light = defaults.string(forKey: Key.lightSkinID)
        let dark = defaults.string(forKey: Key.darkSkinID)
        if light != nil || dark != nil {
            return SkinPairing(lightID: light ?? SkinPairing.default.lightID, darkID: dark ?? SkinPairing.default.darkID)
        }
        guard let legacy = defaults.string(forKey: Key.skinID) else { return .default }
        let migrated = SkinPairing(migratingSingle: legacy)
        defaults.set(migrated.lightID, forKey: Key.lightSkinID)
        defaults.set(migrated.darkID, forKey: Key.darkSkinID)
        defaults.removeObject(forKey: Key.skinID)
        return migrated
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
