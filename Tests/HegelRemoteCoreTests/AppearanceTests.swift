import Foundation
import Testing
@testable import HegelRemoteCore

@Suite struct AppearanceTests {
    let pairing = SkinPairing.default

    @Test func systemFollowsTheSystemScheme() {
        #expect(SkinResolver.resolve(appearance: .system, systemIsDark: false, pairing: pairing) == .silver)
        #expect(SkinResolver.resolve(appearance: .system, systemIsDark: true, pairing: pairing) == .black)
    }

    @Test func explicitSettingIgnoresTheSystemScheme() {
        for systemDark in [false, true] {
            #expect(SkinResolver.resolve(appearance: .light, systemIsDark: systemDark, pairing: pairing) == .silver)
            #expect(SkinResolver.resolve(appearance: .dark, systemIsDark: systemDark, pairing: pairing) == .black)
        }
    }

    @Test func anySkinFitsEitherSlot() {
        let p = SkinPairing(lightID: "black", darkID: "oled")
        #expect(SkinResolver.resolve(appearance: .light, systemIsDark: false, pairing: p) == .black)
        #expect(SkinResolver.resolve(appearance: .dark, systemIsDark: false, pairing: p) == .oled)
        let swapped = SkinPairing(lightID: "oled", darkID: "silver")
        #expect(SkinResolver.resolve(appearance: .system, systemIsDark: true, pairing: swapped) == .silver)
    }

    @Test func missingSkinFallsBackPerSlot() {
        let p = SkinPairing(lightID: "gone", darkID: "gone")
        #expect(SkinResolver.resolve(appearance: .light, systemIsDark: false, pairing: p) == .silver)
        #expect(SkinResolver.resolve(appearance: .dark, systemIsDark: false, pairing: p) == .black)
    }

    @Test func defaultPairingIsSilverAndBlack() {
        #expect(SkinPairing.default == SkinPairing(lightID: "silver", darkID: "black"))
        #expect(SkinPairing(migratingSingle: "oled") == SkinPairing(lightID: "silver", darkID: "oled"))
        #expect(SkinPairing(migratingSingle: "black") == SkinPairing(lightID: "silver", darkID: "black"))
        #expect(SkinPairing(migratingSingle: "silver") == SkinPairing(lightID: "silver", darkID: "black"))
        #expect(SkinPairing(migratingSingle: "gone") == .default)
    }

    @Test func settingsAndPairingRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(SkinPairing(lightID: "a", darkID: "b"))
        #expect(try JSONDecoder().decode(SkinPairing.self, from: data) == SkinPairing(lightID: "a", darkID: "b"))
        #expect(AppearanceSetting.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }
}

@Suite struct IconChoiceTests {
    @Test func storageRoundTrips() {
        #expect(IconChoice(storageValue: nil) == .default)
        #expect(IconChoice(storageValue: "default") == .default)
        #expect(IconChoice(storageValue: "") == .default)
        #expect(IconChoice(storageValue: "h590") == .model("H590"))
        #expect(IconChoice(storageValue: IconChoice.model("H590").storageValue) == .model("H590"))
        #expect(IconChoice.default.storageValue == "default")
    }

    @Test func platformNames() {
        #expect(IconChoice.default.alternateIconName == nil)
        #expect(IconChoice.model("H590").alternateIconName == "AppIcon-H590")
        #expect(IconChoice.default.dockImageName(dark: false) == "DockIcon-Default-Light")
        #expect(IconChoice.default.dockImageName(dark: true) == "DockIcon-Default-Dark")
        #expect(IconChoice.model("H590").dockImageName(dark: true) == "DockIcon-H590-Dark")
    }

    @Test func onlyModelsWithArtworkAreOffered() {
        #expect(AppIcons.availableModelIcons == ["H590"])
        #expect(AppIcons.choices == [.default, .model("H590")])
        #expect(AppIcons.effective(.model("H390")) == .default)
        #expect(AppIcons.effective(.model("H590")) == .model("H590"))
    }

    @Test func iconForModel() {
        #expect(AppIcons.icon(forModelID: "h590") == .model("H590"))
        #expect(AppIcons.icon(forModelID: "H590") == .model("H590"))
        #expect(AppIcons.icon(forModelID: "h390") == .default)
    }
}
