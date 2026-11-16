import Foundation
import HegelProtocol
import Testing
@testable import HegelRemoteCore

@Suite struct InputCatalogTests {
    let settings: [InputSetting] = [
        InputSetting(number: 1, name: "Pontus", isEnabled: true, playbackTarget: .plexamp(host: "192.168.0.187")),
        InputSetting(number: 2, isEnabled: false),
        InputSetting(number: 7, name: "  ", isEnabled: true),
    ]

    @Test func defaultsApplyWhenNothingIsStored() {
        let items = InputCatalog.items(model: .h590, settings: [])
        #expect(items.count == 12)
        #expect(items[11].name == "Network" && items[11].number == 12)
        #expect(items.allSatisfy { $0.isEnabled && $0.playbackTarget == nil && !$0.isRenamed })
    }

    @Test func renameHideAndTargetAreApplied() {
        let items = InputCatalog.items(model: .h590, settings: settings)
        #expect(items[0].name == "Pontus" && items[0].defaultName == "XLR 1" && items[0].isRenamed)
        #expect(items[0].playbackTarget == .plexamp(host: "192.168.0.187", port: 32500))
        #expect(items[1].isEnabled == false)
        // A blank custom name keeps the default.
        #expect(items[6].name == "Coaxial" && !items[6].isRenamed)
        #expect(InputCatalog.enabledItems(model: .h590, settings: settings).map(\.number) == [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    }

    @Test func modelWithoutInputTableFallsBackToNumbers() {
        let items = InputCatalog.items(model: .rost, settings: [])
        #expect(items.count == 12 && items[0].name == "Input 1")
    }

    @Test func matchByUserNameDefaultNameNumberAndPrefix() {
        #expect(InputCatalog.match(name: "pontus", model: .h590, settings: settings)?.number == 1)
        #expect(InputCatalog.match(name: " XLR 1 ", model: .h590, settings: settings)?.number == 1)
        #expect(InputCatalog.match(name: "network", model: .h590, settings: settings)?.number == 12)
        #expect(InputCatalog.match(name: "input 11", model: .h590, settings: settings)?.number == 11)
        #expect(InputCatalog.match(name: "5", model: .h590, settings: settings)?.number == 5)
        #expect(InputCatalog.match(name: "pont", model: .h590, settings: settings)?.number == 1)
        // "optical" is ambiguous (three of them) and "tv" does not exist.
        #expect(InputCatalog.match(name: "optical", model: .h590, settings: settings) == nil)
        #expect(InputCatalog.match(name: "tv", model: .h590, settings: settings) == nil)
        #expect(InputCatalog.match(name: "", model: .h590, settings: settings) == nil)
    }

    @Test func updatingReplacesTheEntryForThatNumber() {
        let updated = InputCatalog.updating(settings, with: InputSetting(number: 2, name: "TV", isEnabled: true))
        #expect(updated.filter { $0.number == 2 }.count == 1)
        #expect(updated.first { $0.number == 2 }?.name == "TV")
        #expect(updated.map(\.number) == [1, 2, 7])
    }

    @Test func nextWrapsOverEnabledInputsOnly() {
        #expect(InputCatalog.next(after: 1, model: .h590, settings: settings)?.number == 3)
        #expect(InputCatalog.next(after: 12, model: .h590, settings: settings)?.number == 1)
        #expect(InputCatalog.next(after: nil, model: .h590, settings: settings)?.number == 1)
        let allOff = (1...12).map { InputSetting(number: $0, isEnabled: false) }
        #expect(InputCatalog.next(after: 1, model: .h590, settings: allOff) == nil)
    }
}

@Suite struct ModelCapabilitiesTests {
    @Test func everyModelInHegelKitHasACapabilityRow() {
        for model in AmpModel.all {
            #expect(ModelCapabilities.all.contains { $0.modelID == model.id }, "missing row for \(model.id)")
        }
    }

    @Test func onlyH590IsVerified() {
        #expect(ModelCapabilities.all.filter { $0.support == .verified }.map(\.modelID) == ["h590"])
        #expect(ModelCapabilities.capabilities(for: "H390").pickerLabel == "H390 (untested)")
        #expect(ModelCapabilities.capabilities(for: "nope").modelID == "h590")
        #expect(ModelCapabilities.capabilities(for: "h590").supports(.input))
    }
}

@Suite struct AmpAddressTests {
    @Test func parsesHostAndOptionalPort() {
        #expect(AmpAddress.parse("192.168.0.10") == AmpAddress(host: "192.168.0.10"))
        #expect(AmpAddress.parse(" 127.0.0.1:50002 ") == AmpAddress(host: "127.0.0.1", port: 50002))
        #expect(AmpAddress.parse("amp.local")?.host == "amp.local")
        #expect(AmpAddress.parse("") == nil)
        #expect(AmpAddress.parse("1.2.3.4:") == nil)
        #expect(AmpAddress.parse("1.2.3.4:abc") == nil)
        #expect(AmpAddress.parse("fe80::1:50001") == nil)
    }

    @Test func titleAndDisplayHost() {
        #expect(AmpAddress(host: "h").title == "H590")
        #expect(AmpAddress(host: "h", name: "Living room").title == "H590 · Living room")
        #expect(AmpAddress(host: "h", port: 50002).displayHost == "h:50002")
        #expect(AmpAddress(host: "h", modelID: "h390").model == .h390)
        #expect(AmpAddress(host: "h", modelID: "bogus").model == .h590)
    }
}
