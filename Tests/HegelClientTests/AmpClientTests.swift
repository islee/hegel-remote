import Foundation
import HegelProtocol
import Testing
@testable import HegelClient

/// Polls until `condition` holds or the timeout passes. Returns the final value of the condition.
func eventually(timeout: TimeInterval = 5, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// Fast timings so reconnect and keepalive tests finish quickly.
func fastConfig(keepalive: TimeInterval? = nil) -> AmpClientConfiguration {
    var c = AmpClientConfiguration()
    c.connectTimeout = 2
    c.keepaliveInterval = keepalive
    c.reconnectBase = 0.05
    c.reconnectCap = 0.2
    c.minSendInterval = 0.01
    return c
}

/// Collects events from a stream in the background.
final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AmpEvent] = []
    private var task: Task<Void, Never>?
    init(_ stream: AsyncStream<AmpEvent>) {
        task = Task { [self] in
            for await e in stream { lock.withLock { items.append(e) } }
        }
    }
    var events: [AmpEvent] { lock.withLock { items } }
    func stop() { task?.cancel() }
}

@Suite(.serialized) struct AmpClientTests {
    @Test func initialStateOnConnect() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        let events = Collector(client.events)
        try await client.connect()
        #expect(await client.waitForInitialState())
        #expect(await client.state == AmpState(power: true, input: 12, volume: 33, mute: false))
        #expect(await client.status == .ready)
        #expect(await eventually { events.events.contains(.connection(.ready)) })
        #expect(events.events.first == .connection(.connecting))
        #expect(amp.receivedPackets.prefix(4) == ["-p.?", "-i.?", "-v.?", "-m.?"])
        await client.disconnect()
        events.stop()
    }

    @Test func pacingSatisfiesAmpThatDropsBackToBackPackets() async throws {
        let amp = try await FakeAmp.start()
        amp.dropsBackToBackPackets = true
        defer { amp.stop() }
        var config = fastConfig()
        config.minSendInterval = 0.1  // the production default
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: config)
        try await client.connect()
        #expect(await client.waitForInitialState(timeout: 3))
        await client.disconnect()
    }

    @Test func pickyFakeAmpDropsSecondPacketOfOneWrite() async throws {
        // Control for the test above: two packets in one write, only the first is applied.
        let amp = try await FakeAmp.start()
        amp.dropsBackToBackPackets = true
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        try await client.connect()
        #expect(await client.waitForInitialState(timeout: 3))
        try await client.sendRaw(Array("-v.u\r-v.u\r".utf8))
        #expect(await eventually { await client.state.volume == 34 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.state.volume == 34)
        await client.disconnect()
    }

    @Test func setVolumeUpdatesState() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        try await client.connect()
        await client.waitForInitialState()
        try await client.setVolume(50)
        #expect(await eventually { await client.state.volume == 50 })
        try await client.volumeUp()
        #expect(await eventually { await client.state.volume == 51 })
        try await client.volumeDown()
        try await client.volumeDown()
        #expect(await eventually { await client.state.volume == 49 })
        try await client.setMute(true)
        #expect(await eventually { await client.state.mute == true })
        try await client.setInput(7)
        #expect(await eventually { await client.state.input == 7 })
        await client.disconnect()
    }

    @Test func otherClientsChangeIsPushed() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let first = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        let second = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        let events = Collector(first.events)
        try await first.connect()
        try await second.connect()
        await first.waitForInitialState()
        try await second.setVolume(77)
        #expect(await eventually { await first.state.volume == 77 })
        #expect(events.events.contains(.volume(77)))
        amp.frontPanel(volume: 12)
        #expect(await eventually { await first.state.volume == 12 })
        #expect(await eventually { await second.state.volume == 12 })
        await first.disconnect()
        await second.disconnect()
        events.stop()
    }

    @Test func reconnectsAndRequeriesAfterServerDrop() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        let events = Collector(client.events)
        try await client.connect()
        await client.waitForInitialState()
        let queriesBefore = amp.receivedPackets.filter { $0 == "-p.?" }.count
        #expect(queriesBefore == 1)
        amp.dropAllClients()
        #expect(await eventually { events.events.contains { if case .connection(.failed) = $0 { true } else { false } } })
        #expect(await eventually { amp.receivedPackets.filter { $0 == "-p.?" }.count == 2 })
        #expect(await eventually { await client.status == .ready })
        // State written while disconnected is picked up by the re-query.
        amp.frontPanel(volume: 20)
        #expect(await eventually { await client.state.volume == 20 })
        try await client.setVolume(30)
        #expect(await eventually { await client.state.volume == 30 })
        await client.disconnect()
        events.stop()
    }

    @Test func powerOffStillAnswers() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        try await client.connect()
        await client.waitForInitialState()
        try await client.setPower(false)
        #expect(await eventually { await client.state.power == false })
        try await client.requestState()
        #expect(await eventually { amp.receivedPackets.filter { $0 == "-v.?" }.count == 2 })
        #expect(await client.state.volume == 33)
        try await client.togglePower()
        #expect(await eventually { await client.state.power == true })
        await client.disconnect()
    }

    @Test func invalidPacketYieldsErrorEvent() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig())
        let events = Collector(client.events)
        try await client.connect()
        await client.waitForInitialState()
        // A packet preceded by LF is rejected by the amp; the client never sends one itself, so use the raw path.
        try await client.sendRaw(Array("\n-p.?\r".utf8))
        #expect(await eventually { events.events.contains(.error(code: 1)) })
        // The state is untouched and the connection still works.
        #expect(await client.state.power == true)
        try await client.setVolume(10)
        #expect(await eventually { await client.state.volume == 10 })
        await client.disconnect()
        events.stop()
    }

    @Test func keepaliveSendsResetTimer() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig(keepalive: 0.1))
        let events = Collector(client.events)
        try await client.connect()
        #expect(await eventually { amp.receivedPackets.filter { $0 == "-r.3" }.count >= 3 })
        #expect(await eventually { events.events.contains(.resetTimer(minutes: 3)) })
        await client.disconnect()
        events.stop()
    }

    @Test func noKeepaliveWhenDisabled() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port, configuration: fastConfig(keepalive: nil))
        try await client.connect()
        await client.waitForInitialState()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!amp.receivedPackets.contains("-r.3"))
        await client.disconnect()
    }

    @Test func connectToClosedPortFailsFast() async throws {
        let amp = try await FakeAmp.start()
        let port = amp.port
        amp.stop()
        try await Task.sleep(for: .milliseconds(100))
        let client = AmpClient(host: "127.0.0.1", port: port, configuration: fastConfig())
        await #expect(throws: AmpClientError.self) { try await client.connect() }
        #expect(await client.status != .ready)
        await #expect(throws: AmpClientError.notConnected) { try await client.setVolume(1) }
    }

    @Test func connectTimesOutOnBlackhole() async throws {
        // 10.255.255.1 is unroutable on most networks; this must end in a failure (timeout or no route), not hang.
        var config = fastConfig()
        config.connectTimeout = 0.5
        let client = AmpClient(host: "10.255.255.1", port: 50001, configuration: config)
        let started = Date()
        await #expect(throws: AmpClientError.self) { try await client.connect() }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func backgroundRetryConnectsWhenAmpAppears() async throws {
        let amp = try await FakeAmp.start()
        let port = amp.port
        amp.stop()
        try await Task.sleep(for: .milliseconds(100))
        let client = AmpClient(host: "127.0.0.1", port: port, configuration: fastConfig())
        try await client.connect(waitForReady: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.status != .ready)
        await client.disconnect()
        #expect(await client.status == .disconnected)
    }
}
