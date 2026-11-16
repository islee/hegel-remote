// AmpClient.swift: actor that owns one amp connection, its state and its event stream.
//
// Purpose: connect to the amp on TCP 50001, keep `state` current from every received packet
//   (including broadcasts caused by other clients), keep the connection alive, and reconnect.
// Context: Apple-only (Network.framework via Transport). Incoming packets are a state stream, never matched
//   to requests. After a drop the client reconnects with capped exponential backoff and re-queries state.
//   The supervisor Task retains the client until `disconnect()` is called.
// Dependencies: HegelProtocol, Transport.
import Foundation
import HegelProtocol

public struct AmpClientConfiguration: Sendable {
    /// Seconds to reach `.ready` before an attempt is abandoned.
    public var connectTimeout: TimeInterval = 5
    /// Seconds between `-r.<keepaliveMinutes>` packets; nil disables the keepalive entirely.
    /// Hegel recommends `-r.3` every 2 minutes so the amp drops a dead connection.
    public var keepaliveInterval: TimeInterval? = 120
    public var keepaliveMinutes: Int = 3
    public var autoReconnect = true
    /// Reconnect delay is `reconnectBase * 2^attempt`, capped at `reconnectCap` (seconds).
    public var reconnectBase: TimeInterval = 0.5
    public var reconnectCap: TimeInterval = 30
    /// Minimum gap between two writes. Measured on a real H590 (2026-11-16): packets sent back to back
    /// (concatenated or in separate writes) are mostly dropped, only the first is answered; 50 ms apart all four
    /// queries were answered. 100 ms leaves margin.
    public var minSendInterval: TimeInterval = 0.1

    public init() {}
}

public enum AmpClientError: Error, Equatable, Sendable {
    case notConnected
    case connectFailed(String)
    case cancelled
}

/// Fan-out of events to any number of subscribers (each `events` access is its own stream).
final class EventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<AmpEvent>.Continuation] = [:]

    func makeStream() -> AsyncStream<AmpEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: AmpEvent.self)
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func yield(_ event: AmpEvent) {
        let all = lock.withLock { Array(continuations.values) }
        for c in all { c.yield(event) }
    }
}

public actor AmpClient {
    public nonisolated let host: String
    public nonisolated let port: UInt16
    public private(set) var state = AmpState()
    public private(set) var status: ConnectionStatus = .disconnected

    private let config: AmpClientConfiguration
    private let hub = EventHub()
    private var supervisor: Task<Void, Never>?
    private var transport: Transport?
    private var isReady = false
    private var generation = 0
    private var abortOnFirstFailure = false
    private var nextSendAt = Date.distantPast
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    public init(host: String, port: UInt16 = 50001, configuration: AmpClientConfiguration = .init()) {
        self.host = host
        self.port = port
        self.config = configuration
    }

    /// A new stream of every event from now on: decoded packets (own and broadcast) and connection status.
    /// Events before subscription are not replayed; read `state` for the current snapshot.
    public nonisolated var events: AsyncStream<AmpEvent> { hub.makeStream() }

    // MARK: Lifecycle

    /// Starts connecting. With `waitForReady` it returns once connected and throws if the first attempt
    /// fails or times out (no retry loop is left running). Without it, it returns at once and the client
    /// keeps retrying with backoff until `disconnect()`.
    public func connect(waitForReady: Bool = true) async throws {
        if supervisor == nil {
            generation += 1
            abortOnFirstFailure = waitForReady
            supervisor = Task { await self.supervise() }
        }
        guard waitForReady, !isReady else { return }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    public func disconnect() {
        generation += 1
        supervisor?.cancel()
        supervisor = nil
        transport?.cancel()
        transport = nil
        isReady = false
        failWaiters(AmpClientError.cancelled)
        emit(.connection(.disconnected))
    }

    /// Polls until all four state fields are known. Returns false on timeout.
    @discardableResult
    public func waitForInitialState(timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !state.isComplete {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }

    // MARK: Commands

    /// Sends one packet. Throws `notConnected` unless the connection is ready.
    public func send(_ command: Command) async throws {
        try await write(command.bytes)
    }

    /// Paces writes (see `minSendInterval`). The slot is reserved before the first suspension, so concurrent
    /// callers keep their order.
    private func write(_ bytes: [UInt8]) async throws {
        guard isReady, let transport else { throw AmpClientError.notConnected }
        let slot = max(Date(), nextSendAt)
        nextSendAt = slot.addingTimeInterval(config.minSendInterval)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        try await transport.send(Data(bytes))
    }

    /// Writes bytes as given, for protocol experiments and tests (e.g. proving the amp rejects LF noise).
    /// Normal callers use `send(_:)`, which can only produce valid packets.
    public func sendRaw(_ bytes: [UInt8]) async throws {
        try await write(bytes)
    }

    public func setPower(_ on: Bool) async throws { try await send(.power(on ? .on : .off)) }
    public func togglePower() async throws { try await send(.power(.toggle)) }
    public func setVolume(_ percent: Int) async throws { try await send(.volume(.set(percent))) }
    public func volumeUp() async throws { try await send(.volume(.up)) }
    public func volumeDown() async throws { try await send(.volume(.down)) }
    public func setMute(_ on: Bool) async throws { try await send(.mute(on ? .on : .off)) }
    public func toggleMute() async throws { try await send(.mute(.toggle)) }
    public func setInput(_ number: Int) async throws { try await send(.input(.set(number))) }

    /// Re-queries power, input, volume and mute. Replies arrive as ordinary events.
    public func requestState() async throws {
        for command in Command.stateQueries { try await send(command) }
    }

    // MARK: Supervision

    private enum SessionEnd { case neverReady(String), dropped(String) }

    private func supervise() async {
        var attempt = 0
        while !Task.isCancelled {
            emit(.connection(.connecting))
            let end = await runSession()
            if Task.isCancelled { return }
            switch end {
            case .neverReady(let reason):
                emit(.connection(.failed(reason)))
                if abortOnFirstFailure {
                    supervisor = nil
                    failWaiters(AmpClientError.connectFailed(reason))
                    return
                }
            case .dropped(let reason):
                attempt = 0
                emit(.connection(.failed(reason)))
            }
            guard config.autoReconnect else { supervisor = nil; return }
            let delay = min(config.reconnectCap, config.reconnectBase * pow(2, Double(attempt)))
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func runSession() async -> SessionEnd {
        let session = generation
        let t = Transport(host: host, port: port)
        transport = t
        var framer = PacketFramer()
        let timeout = config.connectTimeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            t.cancel(reason: "connect timed out")
        }
        var keepalive: Task<Void, Never>?
        var reachedReady = false
        var reason = "connection closed"
        t.start()
        loop: for await event in t.events {
            switch event {
            case .ready:
                timeoutTask.cancel()
                reachedReady = true
                isReady = true
                nextSendAt = .distantPast
                abortOnFirstFailure = false
                emit(.connection(.ready))
                let waiters = readyWaiters
                readyWaiters = []
                for w in waiters { w.resume() }
                try? await requestState()
                if let interval = config.keepaliveInterval {
                    keepalive = Task { await self.keepaliveLoop(interval: interval) }
                }
            case .waiting(let detail):
                emit(.connection(.waiting(detail)))
            case .data(let bytes):
                for e in framer.feed(bytes) {
                    state.apply(e)
                    hub.yield(e)
                }
            case .failed(let detail):
                reason = detail
                break loop
            case .closed:
                break loop
            }
        }
        timeoutTask.cancel()
        keepalive?.cancel()
        t.cancel()
        if session == generation {
            isReady = false
            transport = nil
        }
        return reachedReady ? .dropped(reason) : .neverReady(reason)
    }

    private func keepaliveLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            try? await send(.resetTimer(.minutes(config.keepaliveMinutes)))
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func emit(_ event: AmpEvent) {
        if case .connection(let s) = event { status = s }
        hub.yield(event)
    }

    private func failWaiters(_ error: Error) {
        let waiters = readyWaiters
        readyWaiters = []
        for w in waiters { w.resume(throwing: error) }
    }
}
