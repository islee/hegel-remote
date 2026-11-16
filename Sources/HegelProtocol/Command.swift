// Command.swift: the request side of the Hegel IP control protocol.
//
// Purpose: turn a typed command into the exact bytes the amp expects (`-<cmd>.<param>\r`).
// Context: pure value types, no I/O. Source of the grammar: Docs/protocol.md.
// Dependencies: none.

/// Set / toggle / query for a two-state setting (power, mute).
public enum SwitchAction: Sendable, Equatable {
    case on, off, toggle, query

    var param: String {
        switch self {
        case .on: "1"
        case .off: "0"
        case .toggle: "t"
        case .query: "?"
        }
    }
}

public enum VolumeAction: Sendable, Equatable {
    /// Percent, clamped to 0...100 when encoded.
    case set(Int)
    case up, down, query
}

public enum InputAction: Sendable, Equatable {
    /// 1-based input number, clamped to >= 1 when encoded. Valid upper bound is model specific.
    case set(Int)
    case query
}

public enum ResetTimerAction: Sendable, Equatable {
    /// Minutes until the amp drops an idle connection, clamped to 0...255 when encoded.
    case minutes(Int)
    case stop, query
}

/// One request packet. `bytes` is what goes on the wire.
public enum Command: Sendable, Equatable {
    case power(SwitchAction)
    case input(InputAction)
    case volume(VolumeAction)
    case mute(SwitchAction)
    case resetTimer(ResetTimerAction)

    /// The four state queries sent on connect.
    public static let stateQueries: [Command] = [
        .power(.query), .input(.query), .volume(.query), .mute(.query),
    ]

    var letter: Character {
        switch self {
        case .power: "p"
        case .input: "i"
        case .volume: "v"
        case .mute: "m"
        case .resetTimer: "r"
        }
    }

    var param: String {
        switch self {
        case .power(let a), .mute(let a):
            a.param
        case .input(let a):
            switch a {
            case .set(let n): String(max(1, n))
            case .query: "?"
            }
        case .volume(let a):
            switch a {
            case .set(let p): String(min(100, max(0, p)))
            case .up: "u"
            case .down: "d"
            case .query: "?"
            }
        case .resetTimer(let a):
            switch a {
            case .minutes(let m): String(min(255, max(0, m)))
            case .stop: "~"
            case .query: "?"
            }
        }
    }

    /// Wire text, e.g. `-v.50\r`. CR only: the amp rejects a packet preceded by LF.
    public var wire: String { "-\(letter).\(param)\r" }

    public var bytes: [UInt8] { Array(wire.utf8) }
}
