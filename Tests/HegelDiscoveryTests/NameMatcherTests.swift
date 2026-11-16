import HegelProtocol
import Testing
@testable import HegelDiscovery

@Suite struct NameMatcherTests {
    @Test func matchesAdvertisedNames() {
        #expect(HegelNameMatcher.model(forServiceName: "D8F710D3E204@H590") == .h590)
        #expect(HegelNameMatcher.model(forServiceName: "H590") == .h590)
        #expect(HegelNameMatcher.model(forServiceName: "Living Room H390") == .h390)
        #expect(HegelNameMatcher.model(forServiceName: "h120") == .h120)
        #expect(HegelNameMatcher.model(forServiceName: "H95") == .h95)
        #expect(HegelNameMatcher.model(forServiceName: "H190") == .h190)
        #expect(HegelNameMatcher.model(forServiceName: "H190V") == .h190)
        #expect(HegelNameMatcher.model(forServiceName: "Röst") == .rost)
        #expect(HegelNameMatcher.model(forServiceName: "Rost") == .rost)
    }

    @Test func rejectsOthers() {
        for name in ["Apple TV", "HomePod", "Frost", "XH590", "H5900", "H950", "Sonos Arc", "", "H5"] {
            #expect(HegelNameMatcher.model(forServiceName: name) == nil, "\(name)")
        }
        #expect(!HegelNameMatcher.isCandidate("Kitchen Speaker"))
        #expect(HegelNameMatcher.isCandidate("AA11@H95"))
    }
}
