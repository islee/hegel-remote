import Foundation
import Testing
@testable import HegelRemoteCore

/// Each test gets its own UserDefaults suite so nothing leaks between tests or into the simulator's app.
@MainActor
func makeDefaults() -> UserDefaults {
    let name = "HegelRemoteTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Suite @MainActor struct SettingsStoreTests {
    @Test func firstLaunchDefaults() {
        let s = SettingsStore(defaults: makeDefaults())
        #expect(s.ampAddress == nil)
        #expect(s.skin == .silver && s.volumeControl == .wheel)
        #expect(s.customButtons == [.exampleLateNight])
        #expect(s.inputs.count == 12 && s.enabledInputs.count == 12)
        #expect(s.plexClientID.hasPrefix("hegel-remote-"))
    }

    @Test func everythingPersistsAcrossInstances() throws {
        let defaults = makeDefaults()
        let a = SettingsStore(defaults: defaults)
        a.ampAddress = AmpAddress(host: "127.0.0.1", port: 50002, modelID: "h390", name: "Desk")
        a.skinPairing = SkinPairing(lightID: "oled", darkID: "black")
        a.appearance = .dark
        a.iconChoice = .model("H590")
        a.iconFollowsModel = false
        a.volumeControlOverride = .slider
        a.update(InputSetting(number: 1, name: "Pontus", isEnabled: true, playbackTarget: .plexamp(host: "192.168.0.187")))
        a.update(InputSetting(number: 2, isEnabled: false))
        a.customButtons = []
        _ = try a.addUserSkin(json: try Skin.oled.encodeJSON().replacingID("custom"))

        let b = SettingsStore(defaults: defaults)
        #expect(b.ampAddress == a.ampAddress)
        #expect(b.model == .h390 && b.capabilities.support == .untested)
        #expect(b.skinPairing == a.skinPairing && b.appearance == .dark && b.skin == .black)
        #expect(b.iconChoice == .model("H590") && b.iconFollowsModel == false)
        #expect(b.volumeControl == .slider)
        #expect(b.input(number: 1)?.name == "Pontus")
        #expect(b.input(number: 1)?.playbackTarget == .plexamp(host: "192.168.0.187", port: 32500))
        #expect(b.enabledInputs.map(\.number).contains(2) == false)
        #expect(b.customButtons.isEmpty, "an emptied list must not come back as the example preset")
        #expect(b.userSkins.map(\.id) == ["custom"] && b.allSkins.count == 4)
        #expect(b.plexClientID == a.plexClientID)
    }

    @Test func launchArgumentStyleScalarsAreRead() {
        // Simulates `-skinID oled (the legacy key) -ampHost 127.0.0.1` from the arguments domain by writing plain keys.
        let defaults = makeDefaults()
        defaults.set("oled", forKey: "skinID")
        defaults.set("127.0.0.1", forKey: "ampHost")
        defaults.set("slider", forKey: "volumeControl")
        let s = SettingsStore(defaults: defaults)
        // A legacy dark skin lands in the dark slot.
        s.systemIsDark = true
        #expect(s.skin == .oled && s.volumeControl == .slider)
        #expect(s.ampAddress == AmpAddress(host: "127.0.0.1"))
    }

    @Test func pairingDefaultsAndLaunchArguments() {
        let s = SettingsStore(defaults: makeDefaults())
        #expect(s.appearance == .system && s.skinPairing == .default)
        #expect(s.skin == .silver)
        s.systemIsDark = true
        #expect(s.skin == .black)
        s.appearance = .light
        #expect(s.skin == .silver)

        // Launch arguments: `-appearance dark -lightSkinID silver -darkSkinID oled`.
        let defaults = makeDefaults()
        defaults.set("dark", forKey: "appearance")
        defaults.set("silver", forKey: "lightSkinID")
        defaults.set("oled", forKey: "darkSkinID")
        #expect(SettingsStore(defaults: defaults).skin == .oled)
    }

    /// A user who picked one skin before the pairing existed keeps it in its matching slot, and the app still
    /// follows the system theme.
    @Test func legacySkinIDMigratesToItsMatchingSlot() {
        let defaults = makeDefaults()
        defaults.set("black", forKey: "skinID")
        let s = SettingsStore(defaults: defaults)
        #expect(s.skinPairing == SkinPairing(lightID: "silver", darkID: "black"))
        #expect(s.appearance == .system)
        s.systemIsDark = false
        #expect(s.skin == .silver)
        s.systemIsDark = true
        #expect(s.skin == .black)
        // Migrated once: the pair is stored, the legacy key is gone, and a later instance reads the pair.
        #expect(defaults.string(forKey: "skinID") == nil)
        s.skinPairing.lightID = "oled"
        let again = SettingsStore(defaults: defaults)
        #expect(again.skinPairing == SkinPairing(lightID: "oled", darkID: "black"))
    }

    /// Build f7c36c7 stored the legacy skin in both slots; that pair is repaired once, then left alone.
    @Test func bothSlotsPairFromEarlierBuildIsRepairedOnce() {
        let defaults = makeDefaults()
        defaults.set("black", forKey: "lightSkinID")
        defaults.set("black", forKey: "darkSkinID")
        let s = SettingsStore(defaults: defaults)
        #expect(s.skinPairing == SkinPairing(lightID: "silver", darkID: "black"))
        // A deliberate same-skin pair chosen after the repair stays.
        s.skinPairing = SkinPairing(lightID: "oled", darkID: "oled")
        let again = SettingsStore(defaults: defaults)
        #expect(again.skinPairing == SkinPairing(lightID: "oled", darkID: "oled"))
    }

    @Test func newKeysBeatTheLegacyKey() {
        let defaults = makeDefaults()
        defaults.set("oled", forKey: "skinID")
        defaults.set("silver", forKey: "lightSkinID")
        let s = SettingsStore(defaults: defaults)
        #expect(s.skinPairing == SkinPairing(lightID: "silver", darkID: SkinPairing.default.darkID))
    }

    @Test func userSkinCanFillASlot() throws {
        let s = SettingsStore(defaults: makeDefaults())
        let custom = try s.addUserSkin(json: try Skin.oled.encodeJSON().replacingID("custom"))
        s.skinPairing.darkID = custom.id
        s.appearance = .dark
        #expect(s.skin.id == "custom")
    }

    @Test func iconFollowsTheModelByDefault() {
        let s = SettingsStore(defaults: makeDefaults())
        // No amp yet: the model falls back to H590, which has an icon.
        #expect(s.iconFollowsModel && s.effectiveIconChoice == .model("H590"))
        s.ampAddress = AmpAddress(host: "h", modelID: "h590")
        #expect(s.effectiveIconChoice == .model("H590"))
        s.ampAddress = AmpAddress(host: "h", modelID: "h390")
        #expect(s.effectiveIconChoice == .default)  // no H390 artwork yet
        // Turning it off applies the stored choice.
        s.iconFollowsModel = false
        #expect(s.effectiveIconChoice == .default)
        s.iconChoice = .model("H590")
        #expect(s.effectiveIconChoice == .model("H590"))
    }

    @Test func forgetAndUnknownSkinFallBack() {
        let s = SettingsStore(defaults: makeDefaults())
        s.ampAddress = AmpAddress(host: "h")
        s.forgetAmp()
        #expect(s.ampAddress == nil)
        s.skinPairing = SkinPairing(lightID: "missing", darkID: "missing")
        #expect(s.skin == .silver)
        s.systemIsDark = true
        #expect(s.skin == .black)
    }
}

extension Data {
    func replacingID(_ id: String) throws -> Data {
        var skin = try Skin.decode(json: self)
        skin.id = id
        return try skin.encodeJSON()
    }
}
