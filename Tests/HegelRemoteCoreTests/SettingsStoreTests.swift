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
        a.skinID = "black"
        a.volumeControlOverride = .slider
        a.update(InputSetting(number: 1, name: "Pontus", isEnabled: true, playbackTarget: .plexamp(host: "192.168.0.187")))
        a.update(InputSetting(number: 2, isEnabled: false))
        a.customButtons = []
        _ = try a.addUserSkin(json: try Skin.oled.encodeJSON().replacingID("custom"))

        let b = SettingsStore(defaults: defaults)
        #expect(b.ampAddress == a.ampAddress)
        #expect(b.model == .h390 && b.capabilities.support == .untested)
        #expect(b.skinID == "black" && b.volumeControl == .slider)
        #expect(b.input(number: 1)?.name == "Pontus")
        #expect(b.input(number: 1)?.playbackTarget == .plexamp(host: "192.168.0.187", port: 32500))
        #expect(b.enabledInputs.map(\.number).contains(2) == false)
        #expect(b.customButtons.isEmpty, "an emptied list must not come back as the example preset")
        #expect(b.userSkins.map(\.id) == ["custom"] && b.allSkins.count == 4)
        #expect(b.plexClientID == a.plexClientID)
    }

    @Test func launchArgumentStyleScalarsAreRead() {
        // Simulates `-skinID oled -ampHost 127.0.0.1` from the arguments domain by writing plain keys.
        let defaults = makeDefaults()
        defaults.set("oled", forKey: "skinID")
        defaults.set("127.0.0.1", forKey: "ampHost")
        defaults.set("slider", forKey: "volumeControl")
        let s = SettingsStore(defaults: defaults)
        #expect(s.skin == .oled && s.volumeControl == .slider)
        #expect(s.ampAddress == AmpAddress(host: "127.0.0.1"))
    }

    @Test func forgetAndUnknownSkinFallBack() {
        let s = SettingsStore(defaults: makeDefaults())
        s.ampAddress = AmpAddress(host: "h")
        s.forgetAmp()
        #expect(s.ampAddress == nil)
        s.skinID = "missing"
        #expect(s.skin == .silver)
    }
}

extension Data {
    func replacingID(_ id: String) throws -> Data {
        var skin = try Skin.decode(json: self)
        skin.id = id
        return try skin.encodeJSON()
    }
}
