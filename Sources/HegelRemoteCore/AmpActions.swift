// AmpActions.swift: the app's amp commands as data, how they are confirmed, and the one-shot session.
//
// Purpose: everything that drives the amp (UI, Siri intents, custom buttons) goes through `AmpAction`, so
//   there is one mapping to protocol commands and one way to wait for the amp's reply. `AmpSession.run`
//   opens a short-lived connection for callers without a live one (intents running with the UI closed).
// Context: the amp answers every command with a state packet, broadcast to all clients, so confirmation is
//   "the next event of that kind", never a request/response pair (Docs/protocol.md). A broadcast from another
//   client can confirm early; the state is right either way.
// Dependencies: HegelProtocol, HegelClient.
import Foundation
import HegelClient
import HegelProtocol

/// A command a user can bind to a button or ask Siri for. Codable so custom buttons persist it.
public enum AmpAction: Hashable, Sendable, Codable {
    case power(Bool)
    case togglePower
    case setVolume(Int)
    case volumeUp
    case volumeDown
    case mute(Bool)
    case toggleMute
    case selectInput(Int)

    public var command: Command {
        switch self {
        case .power(let on): .power(on ? .on : .off)
        case .togglePower: .power(.toggle)
        case .setVolume(let v): .volume(.set(v))
        case .volumeUp: .volume(.up)
        case .volumeDown: .volume(.down)
        case .mute(let on): .mute(on ? .on : .off)
        case .toggleMute: .mute(.toggle)
        case .selectInput(let n): .input(.set(n))
        }
    }

    /// Does this event answer the command? (Same kind of state packet.)
    public func isConfirmed(by event: AmpEvent) -> Bool {
        switch (self, event) {
        case (.power, .power), (.togglePower, .power): true
        case (.setVolume, .volume), (.volumeUp, .volume), (.volumeDown, .volume): true
        case (.mute, .mute), (.toggleMute, .mute): true
        case (.selectInput, .input): true
        default: false
        }
    }

    /// Editor / button-list label.
    public func label(inputName: (Int) -> String?) -> String {
        switch self {
        case .power(let on): on ? "Power on" : "Power off"
        case .togglePower: "Toggle power"
        case .setVolume(let v): "Volume \(v)"
        case .volumeUp: "Volume +"
        case .volumeDown: "Volume −"
        case .mute(let on): on ? "Mute" : "Unmute"
        case .toggleMute: "Toggle mute"
        case .selectInput(let n): inputName(n) ?? "Input \(n)"
        }
    }
}

/// What a runner needs from a connection. `AmpClient` is the only production conformer.
public protocol AmpCommanding: Sendable {
    /// A fresh stream of events from now on; subscribe BEFORE sending.
    var events: AsyncStream<AmpEvent> { get }
    func send(_ command: Command) async throws
    func currentState() async -> AmpState
}

extension AmpClient: AmpCommanding {
    public func currentState() async -> AmpState { state }
}

public enum AmpActionError: Error, Equatable, Sendable {
    case noAmpConfigured
    case noReply(AmpAction)
    case unreachable(String)
}

public enum AmpActionRunner {
    /// Sends the command and returns the amp's confirming event (so callers can report the real value, e.g. a
    /// rounded volume). Throws `noReply` when nothing matching arrives within `timeout`.
    public static func perform(_ action: AmpAction, on amp: any AmpCommanding, timeout: Duration = .seconds(3)) async throws -> AmpEvent {
        let events = amp.events
        try await amp.send(action.command)
        guard let event = await firstEvent(in: events, timeout: timeout, where: { action.isConfirmed(by: $0) }) else {
            throw AmpActionError.noReply(action)
        }
        return event
    }

    /// The first event matching `predicate`, or nil at `timeout`. The losing task is cancelled.
    public static func firstEvent(in events: AsyncStream<AmpEvent>, timeout: Duration,
                                  where predicate: @escaping @Sendable (AmpEvent) -> Bool) async -> AmpEvent? {
        await withTaskGroup(of: AmpEvent?.self) { group in
            group.addTask {
                for await e in events where predicate(e) { return e }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Human sentence for a confirming event, used by Siri dialogs and the Mac menu.
    public static func describe(_ event: AmpEvent, inputName: (Int) -> String?) -> String {
        switch event {
        case .power(let on): on ? "Amplifier is on." : "Amplifier is off."
        case .volume(let v): "Volume is \(v)."
        case .mute(let m): m ? "Muted." : "Unmuted."
        case .input(let n): "Input is \(inputName(n) ?? "\(n)")."
        default: "Done."
        }
    }
}

public enum AmpSession {
    /// Connects to `address`, runs `body`, disconnects. No keepalive, no auto-reconnect: this is for a few
    /// commands and gone, which is what an intent or a custom button needs when the UI is not connected.
    public static func run<T: Sendable>(_ address: AmpAddress, connectTimeout: TimeInterval = 4,
                                        _ body: @Sendable (AmpClient) async throws -> T) async throws -> T {
        var config = AmpClientConfiguration()
        config.connectTimeout = connectTimeout
        config.keepaliveInterval = nil
        config.autoReconnect = false
        let client = AmpClient(host: address.host, port: address.port, configuration: config)
        do {
            try await client.connect()
        } catch {
            throw AmpActionError.unreachable("\(address.displayHost): \(error)")
        }
        defer { Task { await client.disconnect() } }
        return try await body(client)
    }
}
