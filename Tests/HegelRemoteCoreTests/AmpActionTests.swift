import Foundation
import HegelClient
import HegelFakeAmp
import HegelProtocol
import Testing
@testable import HegelRemoteCore

@Suite struct AmpActionTests {
    @Test func actionsMapToWireCommands() {
        #expect(AmpAction.power(true).command.wire == "-p.1\r")
        #expect(AmpAction.togglePower.command.wire == "-p.t\r")
        #expect(AmpAction.setVolume(140).command.wire == "-v.100\r")
        #expect(AmpAction.volumeDown.command.wire == "-v.d\r")
        #expect(AmpAction.mute(false).command.wire == "-m.0\r")
        #expect(AmpAction.selectInput(12).command.wire == "-i.12\r")
    }

    @Test func confirmationMatchesTheSameKindOnly() {
        #expect(AmpAction.setVolume(5).isConfirmed(by: .volume(6)))
        #expect(!AmpAction.setVolume(5).isConfirmed(by: .power(true)))
        #expect(AmpAction.selectInput(1).isConfirmed(by: .input(1)))
        #expect(!AmpAction.toggleMute.isConfirmed(by: .connection(.ready)))
    }

    @Test func actionsAreCodable() throws {
        let all: [AmpAction] = [.power(false), .togglePower, .setVolume(25), .volumeUp, .volumeDown, .mute(true), .toggleMute, .selectInput(3)]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([AmpAction].self, from: data) == all)
    }

    @Test func labelsUseTheUserInputName() {
        #expect(AmpAction.selectInput(1).label(inputName: { $0 == 1 ? "Pontus" : nil }) == "Pontus")
        #expect(AmpAction.selectInput(4).label(inputName: { _ in nil }) == "Input 4")
        #expect(AmpAction.setVolume(25).label(inputName: { _ in nil }) == "Volume 25")
    }

    /// The intent path: one-shot session, send, wait for the amp's reply, describe it.
    @Test func sessionPerformsAndConfirmsAgainstTheFakeAmp() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let address = AmpAddress(host: "127.0.0.1", port: amp.port)

        let sentence = try await AmpSession.run(address) { client in
            let event = try await AmpActionRunner.perform(.setVolume(41), on: client)
            return AmpActionRunner.describe(event, inputName: { _ in nil })
        }
        #expect(sentence == "Volume is 41.")
        #expect(amp.snapshot.volume == 41)

        let input = try await AmpSession.run(address) { client in
            try await AmpActionRunner.perform(.selectInput(1), on: client)
        }
        #expect(input == .input(1))
        #expect(AmpActionRunner.describe(input, inputName: { $0 == 1 ? "Pontus" : nil }) == "Input is Pontus.")
        // Each session queried state (4) and sent one command, with no keepalive.
        #expect(!amp.receivedPackets.contains { $0.hasPrefix("-r.") })
        try await Task.sleep(for: .milliseconds(200))
        #expect(amp.clientCount == 0)
    }

    @Test func sessionToAClosedPortIsUnreachable() async throws {
        let amp = try await FakeAmp.start()
        let port = amp.port
        amp.stop()
        try await Task.sleep(for: .milliseconds(100))
        let address = AmpAddress(host: "127.0.0.1", port: port)
        await #expect(throws: AmpActionError.self) {
            try await AmpSession.run(address, connectTimeout: 2) { _ in 0 }
        }
    }

    @Test func noReplyTimesOut() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port)
        try await client.connect()
        // The fake answers every valid packet, so wait for an event kind no action produces.
        let none = await AmpActionRunner.firstEvent(in: client.events, timeout: .milliseconds(150)) { if case .error = $0 { true } else { false } }
        #expect(none == nil)
        await client.disconnect()
    }
}
