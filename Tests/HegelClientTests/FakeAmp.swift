// FakeAmp: in-process emulation of a Hegel amp for tests (NWListener on 127.0.0.1, ephemeral port).
//
// Mirrors the behaviour verified on a real H590: several simultaneous clients, every state reply broadcast
// to ALL clients, replies to one read concatenated into one write, `-e.1` for anything malformed (including a
// packet preceded by LF), still answers while powered off. The `r` timer is stored and echoed, never enforced
// (the echo format for a set is an assumption). All state is touched only on `queue`.
import Foundation
import Network

final class FakeAmp: @unchecked Sendable {
    struct Snapshot: Equatable { var power = true, input = 12, volume = 33, mute = false, timer = "~" }

    private let queue = DispatchQueue(label: "FakeAmp")
    private var listener: NWListener!
    private var clients: [ObjectIdentifier: (conn: NWConnection, buffer: [UInt8])] = [:]
    private var snap = Snapshot()
    private var log: [String] = []
    private(set) var port: UInt16 = 0
    private var _picky = false

    /// Emulates the real amp's measured quirk: of the packets arriving in one read, only the first is processed.
    var dropsBackToBackPackets: Bool {
        get { queue.sync { _picky } }
        set { queue.sync { _picky = newValue } }
    }

    static func start() async throws -> FakeAmp {
        let amp = FakeAmp()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        amp.listener = try NWListener(using: params)
        amp.listener.newConnectionHandler = { conn in amp.accept(conn) }
        let port: UInt16 = try await withCheckedThrowingContinuation { c in
            let once = NSLock()
            nonisolated(unsafe) var done = false
            amp.listener.stateUpdateHandler = { state in
                once.lock(); defer { once.unlock() }
                guard !done else { return }
                switch state {
                case .ready: done = true; c.resume(returning: amp.listener.port?.rawValue ?? 0)
                case .failed(let e): done = true; c.resume(throwing: e)
                default: break
                }
            }
            amp.listener.start(queue: amp.queue)
        }
        amp.port = port
        return amp
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for c in clients.values { c.conn.cancel() }
            clients.removeAll()
        }
    }

    // MARK: Test hooks

    var snapshot: Snapshot { queue.sync { snap } }
    var receivedPackets: [String] { queue.sync { log } }
    var clientCount: Int { queue.sync { clients.count } }

    /// Closes every client connection; the listener stays up so clients can reconnect.
    func dropAllClients() {
        queue.sync {
            for c in clients.values { c.conn.cancel() }
            clients.removeAll()
        }
    }

    /// A front-panel change: mutate state and broadcast it, as the real amp does.
    func frontPanel(volume: Int) {
        queue.sync {
            snap.volume = volume
            broadcast("-v.\(volume)\r")
        }
    }

    // MARK: Connection handling

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        clients[id] = (conn, [])
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.remove(id) }
            if case .cancelled = state { self?.remove(id) }
        }
        conn.start(queue: queue)
        receive(conn)
    }

    private func remove(_ id: ObjectIdentifier) { clients.removeValue(forKey: id) }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { handle([UInt8](data), from: conn) }
            if error != nil || isComplete { conn.cancel() } else { receive(conn) }
        }
    }

    private func handle(_ bytes: [UInt8], from conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        guard var entry = clients[id] else { return }
        entry.buffer += bytes
        var broadcastOut = ""
        var errorOut = ""
        var processed = 0
        while let cr = entry.buffer.firstIndex(of: 0x0D) {
            let text = String(decoding: entry.buffer[..<cr], as: UTF8.self)
            entry.buffer.removeSubrange(...cr)
            if _picky && processed >= 1 { continue }
            processed += 1
            log.append(text)
            if let reply = apply(text) { broadcastOut += reply } else { errorOut += "-e.1\r" }
        }
        clients[id] = entry
        if !broadcastOut.isEmpty { broadcast(broadcastOut) }
        if !errorOut.isEmpty { conn.send(content: Data(errorOut.utf8), completion: .idempotent) }
    }

    private func broadcast(_ text: String) {
        for c in clients.values { c.conn.send(content: Data(text.utf8), completion: .idempotent) }
    }

    /// Applies one packet (no CR). Returns the reply, or nil for an invalid packet.
    private func apply(_ text: String) -> String? {
        // Strict grammar: exactly `-<letter>.<param>`; a leading LF (or any noise) is invalid.
        let c = Array(text)
        guard c.count >= 4, c[0] == "-", c[2] == "." else { return nil }
        let param = String(c[3...])
        switch c[1] {
        case "p":
            switch param {
            case "1": snap.power = true
            case "0": snap.power = false
            case "t": snap.power.toggle()
            case "?": break
            default: return nil
            }
            return "-p.\(snap.power ? 1 : 0)\r"
        case "m":
            switch param {
            case "1": snap.mute = true
            case "0": snap.mute = false
            case "t": snap.mute.toggle()
            case "?": break
            default: return nil
            }
            return "-m.\(snap.mute ? 1 : 0)\r"
        case "v":
            if let n = Int(param), (0...100).contains(n) { snap.volume = n }
            else if param == "u" { snap.volume = min(100, snap.volume + 1) }
            else if param == "d" { snap.volume = max(0, snap.volume - 1) }
            else if param != "?" { return nil }
            return "-v.\(snap.volume)\r"
        case "i":
            if let n = Int(param), (1...12).contains(n) { snap.input = n }
            else if param != "?" { return nil }
            return "-i.\(snap.input)\r"
        case "r":
            if param != "?" { snap.timer = param }
            return "-r.\(snap.timer)\r"
        default:
            return nil
        }
    }
}
