import Foundation
import Testing
@testable import HegelRemoteCore

@Suite struct SkinTests {
    @Test func hexColourParsesAndRoundTrips() {
        let c = HexColor(hex: "#D9A441")!
        #expect(abs(c.red - 217.0 / 255) < 0.001)
        #expect(abs(c.green - 164.0 / 255) < 0.001)
        #expect(abs(c.blue - 65.0 / 255) < 0.001)
        #expect(c.alpha == 1)
        #expect(c.hex == "#D9A441")
        #expect(HexColor(hex: "0c0d0e")?.hex == "#0C0D0E")
        #expect(HexColor(hex: "#00000080")!.alpha < 0.51)
        #expect(HexColor(hex: "red") == nil)
        #expect(HexColor(hex: "#12345") == nil)
    }

    @Test func builtInsAreDistinctAndMatchTheCanvas() {
        #expect(Skin.builtIns.map(\.id) == ["silver", "black", "oled"])
        #expect(Set(Skin.builtIns.map(\.id)).count == 3)
        #expect(Skin.black.colors.accent.hex == "#D9A441")
        #expect(Skin.silver.isDark == false)
        #expect(Skin.black.isDark && Skin.oled.isDark)
        #expect(Skin.builtIns.allSatisfy { $0.volumeControl == .wheel && $0.readoutFont == .doto })
    }

    @Test func skinJSONRoundTrips() throws {
        for skin in Skin.builtIns {
            let data = try skin.encodeJSON()
            #expect(try Skin.decode(json: data) == skin)
        }
    }

    /// The user-skin contract: a hand-written JSON file decodes with no code changes.
    @Test func userSkinFileDecodes() throws {
        let json = """
        {
          "id": "walnut", "name": "Walnut", "readoutFont": "systemMonospaced", "volumeControl": "slider",
          "colors": {
            "background": "#3b2a1e", "foreground": "#f1e6d8", "muted": "#b39b84", "line": "#5a4634",
            "button": "#4a3627", "accent": "#e0b96b", "readoutBackground": "#000000", "readoutForeground": "#ffd27a",
            "ringHighlight": "#7a5c44", "ringMid": "#5a4634", "ringShadow": "#2e2016", "shadow": "#000000"
          }
        }
        """
        let skin = try Skin.decode(json: Data(json.utf8))
        #expect(skin.id == "walnut")
        #expect(skin.volumeControl == .slider)
        #expect(skin.readoutFont == .systemMonospaced)
        #expect(skin.colors.accent.hex == "#E0B96B")
        #expect(skin.isDark)
    }

    @Test func badColourInSkinFileIsRejected() {
        let json = #"{"id":"x","name":"X","readoutFont":"doto","volumeControl":"wheel","colors":{"background":"blue"}}"#
        #expect(throws: (any Error).self) { try Skin.decode(json: Data(json.utf8)) }
    }
}
