import Foundation
import HegelClient
import HegelFakeAmp
import HegelProtocol
import Testing
@testable import HegelRemoteCore

/// Controller against the in-process FakeAmp: real sockets, real pacing, no UI.
@Suite @MainActor struct AmpControllerTests {
    /// Fast reconnect so the unreachable test does not wait on the default backoff.
    static let makeClient: @Sendable (AmpAddress) -> AmpClient = { address in
        var config = AmpClientConfiguration()
        config.connectTimeout = 1
        config.reconnectBase = 0.1
        config.reconnectCap = 0.2
        return AmpClient(host: address.host, port: address.port, configuration: config)
    }

    func makeController(amp: FakeAmp, settings: SettingsStore? = nil) -> AmpController {
        let s = settings ?? SettingsStore(defaults: makeDefaults())
        s.ampAddress = AmpAddress(host: "127.0.0.1", port: amp.port)
        return AmpController(settings: s, makeClient: Self.makeClient)
    }

    func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func connectsAndMirrorsInitialState() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        #expect(c.phase == .idle)
        c.connect()
        #expect(c.phase == .connecting)
        #expect(await waitUntil { c.isConnected && c.amp.isComplete })
        #expect(c.amp == AmpState(power: true, input: 12, volume: 33, mute: false))
        #expect(c.displayVolume == 33)
        #expect(c.currentInput?.name == "Network")
        #expect(c.playbackUnavailableReason == PlaybackDrivers.noTargetReason)
        c.disconnect()
        #expect(c.phase == .idle)
    }

    @Test func noSavedAmpMeansConnectIsANoOp() {
        let c = AmpController(settings: SettingsStore(defaults: makeDefaults()), makeClient: Self.makeClient)
        c.connect()
        #expect(c.phase == .idle)
        c.setVolume(10)
        #expect(c.pendingVolume == nil)
        c.perform(.togglePower)
        #expect(c.lastError == "Not connected.")
    }

    @Test func frontPanelBroadcastsUpdateTheController() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })
        amp.frontPanel(volume: 50)
        amp.frontPanel(input: 1)
        amp.frontPanel(power: false)
        #expect(await waitUntil { c.amp.volume == 50 && c.amp.input == 1 && c.amp.power == false })
        c.disconnect()
    }

    @Test func wheelDetentsCoalesceIntoFewPacedWrites() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })
        amp.clearLog()

        for _ in 1...10 { c.nudgeVolume(by: 1) }
        #expect(c.pendingVolume == 43, "the readout follows the finger immediately")
        #expect(c.displayVolume == 43)
        #expect(await waitUntil { c.amp.volume == 43 && c.pendingVolume == nil })
        let writes = amp.receivedPackets.filter { $0.hasPrefix("-v.") }
        #expect(writes.last == "-v.43")
        #expect(writes.count <= 3, "10 detents must not become 10 packets: \(writes)")
        c.disconnect()
    }

    @Test func volumeIsClampedToTheModelRange() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })
        c.setVolume(250)
        #expect(c.pendingVolume == 100)
        #expect(await waitUntil { c.amp.volume == 100 })
        c.nudgeVolume(by: -500)
        #expect(await waitUntil { c.amp.volume == 0 && c.pendingVolume == nil })
        c.disconnect()
    }

    @Test func commandsReachTheAmp() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let settings = SettingsStore(defaults: makeDefaults())
        settings.update(InputSetting(number: 2, isEnabled: false))
        let c = makeController(amp: amp, settings: settings)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })

        c.togglePower()
        #expect(await waitUntil { c.amp.power == false })
        c.setPower(true)
        #expect(await waitUntil { c.amp.power == true })
        c.toggleMute()
        #expect(await waitUntil { c.amp.mute == true })
        c.selectInput(1)
        #expect(await waitUntil { c.amp.input == 1 })
        // Next skips the disabled input 2.
        c.selectNextInput()
        #expect(await waitUntil { c.amp.input == 3 })
        #expect(c.inputs.map(\.number).contains(2) == false)
        c.disconnect()
    }

    @Test func unreachableAmpIsReportedAndRecoversWhenItAppears() async throws {
        let probe = try await FakeAmp.start()
        let port = probe.port
        probe.stop()
        try await Task.sleep(for: .milliseconds(100))

        let settings = SettingsStore(defaults: makeDefaults())
        settings.ampAddress = AmpAddress(host: "127.0.0.1", port: port)
        let c = AmpController(settings: settings, makeClient: Self.makeClient)
        c.connect()
        #expect(await waitUntil(.seconds(4)) { if case .unreachable = c.phase { true } else { false } })

        let amp = try await FakeAmp.start(port: port)
        defer { amp.stop() }
        #expect(await waitUntil(.seconds(4)) { c.isConnected && c.amp.isComplete })
        c.disconnect()
    }

    @Test func reconnectAfterAddressChangeAndBackgroundCycle() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        c.connect()
        #expect(await waitUntil { c.isConnected })
        c.appDidEnterBackground()
        #expect(c.phase == .idle)
        #expect(await waitUntil { amp.clientCount == 0 })
        c.appDidBecomeActive()
        #expect(await waitUntil { c.isConnected && c.amp.isComplete })
        c.reconnect()
        #expect(await waitUntil { c.isConnected && c.amp.isComplete })
        c.disconnect()
    }

    @Test func playbackDriverFollowsTheCurrentInputAndPolls() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        server.respond { _ in (200, PlexTimelineTests.liveSample.replacingOccurrences(of: "\"stopped\" time", with: "\"paused\" time")) }

        let settings = SettingsStore(defaults: makeDefaults())
        settings.update(InputSetting(number: 1, name: "Pontus", playbackTarget: .plexamp(host: "127.0.0.1", port: Int(server.port))))
        let c = makeController(amp: amp, settings: settings)
        c.playbackPollInterval = .milliseconds(100)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })
        #expect(c.playbackUnavailableReason != nil, "Network has no target")

        amp.frontPanel(input: 1)
        #expect(await waitUntil { c.playbackUnavailableReason == nil })
        #expect(await waitUntil { c.playbackState?.phase == .paused })

        c.playback(.playPause)
        #expect(await waitUntil { server.received.contains { $0.path.hasPrefix("/player/playback/playPause") } })

        // Mapping removed in settings: the row goes back to disabled after settingsDidChange().
        settings.update(InputSetting(number: 1, name: "Pontus"))
        c.settingsDidChange()
        #expect(c.playbackUnavailableReason == PlaybackDrivers.noTargetReason)
        #expect(await waitUntil { c.playbackState == nil })
        c.disconnect()
    }

    @Test func customButtonRunsThroughTheLiveConnection() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let c = makeController(amp: amp)
        c.connect()
        #expect(await waitUntil { c.amp.isComplete })
        c.run(.exampleLateNight)
        #expect(await waitUntil { c.amp.input == 12 && c.amp.volume == 25 })
        #expect(c.lastError == nil)
        c.disconnect()
    }

    @Test func errorMessagesAreHuman() {
        #expect(AmpController.message(for: AmpActionError.noReply(.volumeUp)) == "The amplifier did not answer (Volume +).")
        #expect(AmpController.message(for: PlaybackError.httpStatus(503)) == "The device answered HTTP 503.")
        #expect(AmpController.message(for: CustomButtonError.noConnection) == "Not connected to the amplifier.")
    }
}
