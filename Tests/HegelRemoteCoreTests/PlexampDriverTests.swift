import Foundation
import Testing
@testable import HegelRemoteCore

@Suite struct PlexTimelineTests {
    /// Verbatim from the owner's Plexamp headless (192.168.0.187:32500) on 2026-11-16, read-only GET.
    static let liveSample = """
    <MediaContainer commandID="1"><Timeline state="stopped" time="0" type="music" itemType="music" volume="100" shuffle="0" repeat="0" controllable="volume,repeat,skipPrevious,seekTo,stepBack,stepForward,stop,playPause"/><Timeline type="video" state="stopped"/><Timeline type="photo" state="stopped"/></MediaContainer>
    """

    @Test func parsesTheLiveSample() {
        #expect(PlexTimeline.parse(Data(Self.liveSample.utf8)) == PlaybackState(phase: .stopped))
    }

    @Test func picksTheMusicTimelineRegardlessOfOrderAndReadsTitle() {
        let xml = """
        <MediaContainer><Timeline type="video" state="paused"/><Timeline state="playing" title="Blue in Green &amp; more" type="music"/></MediaContainer>
        """
        #expect(PlexTimeline.parse(Data(xml.utf8)) == PlaybackState(phase: .playing, title: "Blue in Green & more"))
    }

    @Test func unknownOrMissingMusicTimelineIsNil() {
        #expect(PlexTimeline.parse(Data("<MediaContainer><Timeline type=\"video\" state=\"playing\"/></MediaContainer>".utf8)) == nil)
        #expect(PlexTimeline.parse(Data("<Timeline type=\"music\" state=\"buffering\"/>".utf8)) == nil)
        #expect(PlexTimeline.parse(Data("garbage".utf8)) == nil)
    }
}

@Suite struct PlexampDriverTests {
    @Test func commandsHitTheCompanionEndpointsWithIncreasingCommandIDs() async throws {
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        let driver = PlexampDriver(host: "127.0.0.1", port: Int(server.port), http: URLSessionHTTPClient(timeout: 3), clientID: "test-client")
        #expect(driver.unavailableReason == nil && driver.reportsState)

        try await driver.send(.playPause)
        try await driver.send(.next)
        try await driver.send(.previous)

        let paths = server.received.map(\.path)
        #expect(paths == [
            "/player/playback/playPause?type=music&commandID=1",
            "/player/playback/skipNext?type=music&commandID=2",
            "/player/playback/skipPrevious?type=music&commandID=3",
        ])
        #expect(server.received.allSatisfy { $0.method == "GET" })
        #expect(server.received[0].headers["x-plex-client-identifier"] == "test-client")
        #expect(server.received[0].headers["x-plex-device-name"] == "hegel-remote")
    }

    @Test func pollReturnsParsedStateFromTheTimelineEndpoint() async throws {
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        server.respond { _ in (200, PlexTimelineTests.liveSample.replacingOccurrences(of: "state=\"stopped\" time", with: "state=\"playing\" time")) }
        let driver = PlexampDriver(host: "127.0.0.1", port: Int(server.port), http: URLSessionHTTPClient(timeout: 3), clientID: "c")
        let state = try await driver.poll()
        #expect(state == PlaybackState(phase: .playing))
        #expect(server.received.first?.path == "/player/timeline/poll?wait=0&type=music&commandID=1")
    }

    @Test func nonSuccessStatusThrows() async throws {
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        server.respond { _ in (500, "") }
        let driver = PlexampDriver(host: "127.0.0.1", port: Int(server.port), http: URLSessionHTTPClient(timeout: 3), clientID: "c")
        await #expect(throws: PlaybackError.httpStatus(500)) { try await driver.send(.next) }
    }
}

@Suite struct PlaybackDriversTests {
    let http = URLSessionHTTPClient()

    @Test func noTargetGivesTheDisabledDriverWithAReason() async {
        let d = PlaybackDrivers.make(nil, http: http, clientID: "c")
        #expect(d.unavailableReason == PlaybackDrivers.noTargetReason)
        #expect(d.reportsState == false)
        await #expect(throws: PlaybackError.self) { try await d.send(.playPause) }
    }

    @Test func plexampTargetGivesThePlexampDriver() {
        #expect(PlaybackDrivers.make(.plexamp(host: "h"), http: http, clientID: "c") is PlexampDriver)
    }

    @Test func macMediaKeysIsUnavailableOffTheMac() {
        let d = PlaybackDrivers.make(.macMediaKeys, http: http, clientID: "c")
        #if os(macOS)
        #expect(d.unavailableReason == nil)
        #else
        #expect(d.unavailableReason?.contains("Mac") == true)
        #expect(PlaybackTarget.Kind.availableHere == [.plexamp])
        #endif
    }

    @Test func targetIsCodableAndCaptioned() throws {
        let t = PlaybackTarget.plexamp(host: "192.168.0.187")
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(PlaybackTarget.self, from: data) == t)
        #expect(t.caption == "Plexamp at 192.168.0.187")
        #expect(PlaybackTarget.plexamp(host: "h", port: 1).caption == "Plexamp at h:1")
        #expect(t.kind == .plexamp)
    }
}
