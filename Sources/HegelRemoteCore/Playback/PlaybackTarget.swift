// PlaybackTarget.swift: the playback adapter: one protocol, targets as data, one driver per kind.
//
// Purpose: the Hegel IP protocol has NO transport commands (probed a-z on the real amp, 2026-11-16: only
//   p/i/v/m/r answer; everything else returns `-e.2`). Prev/Play-Pause/Next therefore go to whatever device
//   feeds the current input. The user maps each input to a `PlaybackTarget`; `PlaybackDrivers.make` picks the
//   driver for its kind. A new kind = one enum case + one driver, nothing else changes.
// Context: pure model plus the registry. Drivers live beside this file. The "none" case is a real driver that
//   reports why it is disabled, so views have one code path.
// Dependencies: Foundation.
import Foundation

public enum PlaybackCommand: String, Codable, Sendable, CaseIterable {
    case previous, playPause, next
}

/// Where playback commands for an input go. Stored per input in `InputSetting`.
public enum PlaybackTarget: Hashable, Sendable, Codable {
    /// Plexamp (headless or desktop) via its Plex Companion player API on `port` (32500 by default).
    case plexamp(host: String, port: Int)
    /// The Mac's own media keys; drives whatever app has the Now Playing session. macOS only.
    case macMediaKeys

    public static func plexamp(host: String) -> PlaybackTarget { .plexamp(host: host, port: 32500) }

    public var kind: Kind {
        switch self {
        case .plexamp: .plexamp
        case .macMediaKeys: .macMediaKeys
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case plexamp, macMediaKeys
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .plexamp: "Plexamp"
            case .macMediaKeys: "Mac media keys"
            }
        }
        /// Kinds the running platform can drive; the editor offers only these.
        public static var availableHere: [Kind] {
            #if os(macOS)
            return [.plexamp, .macMediaKeys]
            #else
            return [.plexamp]
            #endif
        }
    }

    /// Short caption for the playback row: "Plexamp at 192.168.0.187".
    public var caption: String {
        switch self {
        case .plexamp(let host, let port): port == 32500 ? "Plexamp at \(host)" : "Plexamp at \(host):\(port)"
        case .macMediaKeys: "Mac media keys"
        }
    }
}

public struct PlaybackState: Hashable, Sendable {
    public enum Phase: String, Sendable { case playing, paused, stopped }
    public var phase: Phase
    public var title: String?
    public init(phase: Phase, title: String? = nil) {
        self.phase = phase
        self.title = title
    }
    public var isPlaying: Bool { phase == .playing }
}

/// One driver per `PlaybackTarget.Kind`. Everything is async because every real driver talks to a device.
public protocol PlaybackDriver: Sendable {
    /// nil when the driver can act; otherwise the one-line reason the playback row shows disabled.
    var unavailableReason: String? { get }
    /// Whether `poll()` can report state (Plexamp can; media keys cannot).
    var reportsState: Bool { get }
    func send(_ command: PlaybackCommand) async throws
    func poll() async throws -> PlaybackState?
}

/// The disabled row: no target for this input, or a target this platform cannot drive.
public struct UnavailablePlaybackDriver: PlaybackDriver {
    public let unavailableReason: String?
    public let reportsState = false
    public init(reason: String) { unavailableReason = reason }
    public func send(_ command: PlaybackCommand) async throws { throw PlaybackError.unavailable(unavailableReason ?? "") }
    public func poll() async throws -> PlaybackState? { nil }
}

public enum PlaybackError: Error, Equatable, Sendable {
    case unavailable(String)
    case badURL(String)
    case httpStatus(Int)
}

public enum PlaybackDrivers {
    public static let noTargetReason = "No playback target for this input. Map one in Settings > Inputs."

    /// The one place that maps a target to its driver.
    public static func make(_ target: PlaybackTarget?, http: any HTTPClient, clientID: String) -> any PlaybackDriver {
        guard let target else { return UnavailablePlaybackDriver(reason: noTargetReason) }
        switch target {
        case .plexamp(let host, let port):
            return PlexampDriver(host: host, port: port, http: http, clientID: clientID)
        case .macMediaKeys:
            #if os(macOS)
            return MacMediaKeysDriver()
            #else
            return UnavailablePlaybackDriver(reason: "Mac media keys work only in the Mac app.")
            #endif
        }
    }
}
