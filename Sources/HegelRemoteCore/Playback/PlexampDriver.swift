// PlexampDriver.swift: playback via Plexamp's Plex Companion player API (headless or desktop Plexamp).
//
// Purpose: Prev / Play-Pause / Next for an input fed by Plexamp, plus the playing/paused/stopped state.
// Context: endpoints, from the Plex Companion protocol as used by Plex clients:
//     GET /player/playback/{playPause|skipNext|skipPrevious}?type=music&commandID=<n>
//     GET /player/timeline/poll?wait=0&type=music&commandID=<n>
//   VERIFIED (2026-11-16, read-only, Plexamp headless on 192.168.0.187:32500): the timeline endpoint answers
//   `<MediaContainer commandID="1"><Timeline state="stopped" type="music" ... controllable="...,skipPrevious,...,playPause"/>...`.
//   UNVERIFIED: the playback endpoints and whether the X-Plex-* headers are required; the real player was never
//   sent a command during development (owner's rule). Tested against a fake HTTP server (AppTests).
//   commandID must increase per request within a client identifier, hence the actor.
// Dependencies: HTTPClient, PlaybackTarget.
import Foundation

public actor PlexampDriver: PlaybackDriver {
    public static let defaultPort = 32500

    let host: String
    let port: Int
    let http: any HTTPClient
    let clientID: String
    private var commandID = 0

    public nonisolated let unavailableReason: String? = nil
    public nonisolated let reportsState = true

    public init(host: String, port: Int = PlexampDriver.defaultPort, http: any HTTPClient, clientID: String) {
        self.host = host
        self.port = port
        self.http = http
        self.clientID = clientID
    }

    static func path(for command: PlaybackCommand) -> String {
        switch command {
        case .playPause: "/player/playback/playPause"
        case .next: "/player/playback/skipNext"
        case .previous: "/player/playback/skipPrevious"
        }
    }

    public func send(_ command: PlaybackCommand) async throws {
        _ = try await get(Self.path(for: command), query: [("type", "music")])
    }

    public func poll() async throws -> PlaybackState? {
        let data = try await get("/player/timeline/poll", query: [("wait", "0"), ("type", "music")])
        return PlexTimeline.parse(data)
    }

    private func get(_ path: String, query: [(String, String)]) async throws -> Data {
        commandID += 1
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } + [URLQueryItem(name: "commandID", value: String(commandID))]
        guard let url = components.url else { throw PlaybackError.badURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Plex Companion identification. The player is a direct target, so no X-Plex-Target-Client-Identifier.
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("hegel-remote", forHTTPHeaderField: "X-Plex-Device-Name")
        request.setValue("hegel-remote", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.perform(request)
        guard (200..<300).contains(response.statusCode) else { throw PlaybackError.httpStatus(response.statusCode) }
        return data
    }
}

/// Parses the music `Timeline` element of a Plex Companion timeline response.
public enum PlexTimeline {
    /// nil when no `type="music"` Timeline is present or its state is unknown.
    public static func parse(_ data: Data) -> PlaybackState? {
        let text = String(decoding: data, as: UTF8.self)
        guard let element = timelineElement(type: "music", in: text),
              let state = attribute("state", in: element) else { return nil }
        let phase: PlaybackState.Phase
        switch state {
        case "playing": phase = .playing
        case "paused": phase = .paused
        case "stopped": phase = .stopped
        default: return nil
        }
        return PlaybackState(phase: phase, title: attribute("title", in: element))
    }

    /// The `<Timeline ... type="<type>" ... />` tag text, attribute order independent.
    static func timelineElement(type: String, in xml: String) -> String? {
        var search = xml[...]
        while let open = search.range(of: "<Timeline") {
            guard let close = search[open.upperBound...].range(of: ">") else { return nil }
            let tag = String(search[open.lowerBound..<close.upperBound])
            if attribute("type", in: tag) == type { return tag }
            search = search[close.upperBound...]
        }
        return nil
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: " \(name)=\"") else { return nil }
        let rest = tag[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
