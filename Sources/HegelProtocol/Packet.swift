// Packet.swift: the reply side of the protocol, plus the incremental framer.
//
// Purpose: turn arbitrary TCP chunks into Packet / AmpEvent values.
// Context: the amp's replies can arrive concatenated in one read (`-p.1\r-i.12\r`) or split across
//   reads, and are broadcast to every client, so incoming packets are a state stream, not
//   request/response pairs. Unknown or malformed input never crashes: it becomes `.unrecognized`.
// Dependencies: none (Foundation not needed).

/// A well-formed `-<cmd>.<param>` packet with the CR stripped.
public struct Packet: Sendable, Equatable {
    public var command: Character
    public var param: String

    public init(command: Character, param: String) {
        self.command = command
        self.param = param
    }

    /// Parses one already-delimited segment. Surrounding whitespace (LF, space, tab) is ignored.
    /// Returns nil unless the text is exactly `-<one char>.<param>`.
    public init?(parsing text: String) {
        let trimmed = Packet.trim(text)
        let chars = Array(trimmed)
        guard chars.count >= 3, chars[0] == "-", chars[1] != ".", chars[2] == "." else { return nil }
        self.command = chars[1]
        self.param = String(chars[3...])
    }

    static func trim(_ text: String) -> String {
        let junk: Set<Character> = ["\n", " ", "\t", "\0", "\r"]
        var s = Substring(text)
        while let f = s.first, junk.contains(f) { s.removeFirst() }
        while let l = s.last, junk.contains(l) { s.removeLast() }
        return String(s)
    }
}

/// Connection lifecycle, surfaced through the same event stream as amp traffic.
public enum ConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case ready
    /// The network path is not available yet (Network.framework `.waiting`); it may recover by itself.
    case waiting(String)
    case failed(String)
}

/// Everything a client can observe: decoded amp packets and connection status.
public enum AmpEvent: Sendable, Equatable {
    case power(Bool)
    case input(Int)
    case volume(Int)
    case mute(Bool)
    /// Reset-connection timer in minutes; nil means stopped (`-r.~`).
    case resetTimer(minutes: Int?)
    /// `-e.<n>`: the amp rejected a packet (observed `-e.1`).
    case error(code: Int)
    /// Anything that did not parse or has an unknown command or parameter. Carries the raw text.
    case unrecognized(String)
    case connection(ConnectionStatus)

    /// Decodes a packet. Unknown commands and bad parameters yield `.unrecognized`.
    public init(packet: Packet) {
        let raw = "-\(packet.command).\(packet.param)"
        let p = packet.param
        switch packet.command {
        case "p":
            if p == "1" { self = .power(true) } else if p == "0" { self = .power(false) } else { self = .unrecognized(raw) }
        case "m":
            if p == "1" { self = .mute(true) } else if p == "0" { self = .mute(false) } else { self = .unrecognized(raw) }
        case "i":
            if let n = Int(p), n >= 0 { self = .input(n) } else { self = .unrecognized(raw) }
        case "v":
            if let n = Int(p), (0...100).contains(n) { self = .volume(n) } else { self = .unrecognized(raw) }
        case "r":
            if p == "~" { self = .resetTimer(minutes: nil) }
            else if let n = Int(p), (0...255).contains(n) { self = .resetTimer(minutes: n) }
            else { self = .unrecognized(raw) }
        case "e":
            if let n = Int(p) { self = .error(code: n) } else { self = .unrecognized(raw) }
        default:
            self = .unrecognized(raw)
        }
    }
}

/// Incremental CR-delimited framer. Feed any byte chunks; get the packets completed by each chunk.
public struct PacketFramer: Sendable {
    /// Without a CR for this many bytes the buffer is discarded, so garbage cannot grow it forever.
    public static let maxPending = 1024

    private var buffer: [UInt8] = []

    public init() {}

    /// Bytes held back waiting for a CR.
    public var pendingByteCount: Int { buffer.count }

    /// Complete segments (text between CRs) found after appending `bytes`. Empty segments are dropped.
    private mutating func segments(_ bytes: some Sequence<UInt8>) -> [String] {
        buffer.append(contentsOf: bytes)
        var out: [String] = []
        while let cr = buffer.firstIndex(of: 0x0D) {
            let text = Packet.trim(String(decoding: buffer[..<cr], as: UTF8.self))
            buffer.removeSubrange(...cr)
            if !text.isEmpty { out.append(text) }
        }
        if buffer.count > Self.maxPending { buffer.removeAll() }
        return out
    }

    /// Well-formed packets only; malformed segments are silently dropped.
    public mutating func feedPackets(_ bytes: some Sequence<UInt8>) -> [Packet] {
        segments(bytes).compactMap { Packet(parsing: $0) }
    }

    /// Every segment as an event: well-formed ones decoded, malformed ones as `.unrecognized`.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [AmpEvent] {
        segments(bytes).map { text in
            Packet(parsing: text).map { AmpEvent(packet: $0) } ?? .unrecognized(text)
        }
    }
}
