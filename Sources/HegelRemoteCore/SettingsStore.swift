// SettingsStore.swift: everything the app persists, as one observable object over UserDefaults.
//
// Purpose: a single source of truth for the remembered amp, skin choice, control choice, input settings,
//   custom buttons and user skins. Views bind to it; intents read it; tests give it an isolated suite.
// Context: free-account signing (no App Groups), so plain UserDefaults is enough: intents run inside the app
//   process. Scalars are stored under plain keys so launch arguments (`-skinID silver`) override them, which
//   the screenshot script relies on; collections are JSON blobs.
// Dependencies: Foundation, HegelProtocol, the Core model types.
import Foundation
import HegelProtocol

@MainActor @Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    enum Key {
        static let ampHost = "ampHost", ampPort = "ampPort", ampModelID = "ampModelID", ampName = "ampName"
        static let skinID = "skinID", volumeControl = "volumeControl"
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

    public var skinID: String {
        didSet { defaults.set(skinID, forKey: Key.skinID) }
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
        skinID = defaults.string(forKey: Key.skinID) ?? Skin.defaultID
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

    public var skin: Skin { allSkins.first { $0.id == skinID } ?? Skin.silver }

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

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
