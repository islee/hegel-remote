// HTTPClient.swift: the one HTTP seam for the Plexamp driver and custom-button HTTP actions.
//
// Purpose: keep URLSession behind a protocol so tests can point drivers at a fake server (or stub the call),
//   and so the apps have one place for timeouts.
// Context: LAN only (http:// to private hosts). The Info.plist allows arbitrary loads for that reason.
// Dependencies: Foundation.
import Foundation

public protocol HTTPClient: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    public init(timeout: TimeInterval = 5) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// A user-defined HTTP call (custom buttons; Home Assistant webhooks later). Data, so it persists as JSON.
public struct HTTPRequestSpec: Hashable, Sendable, Codable {
    public var method: String
    public var url: String
    public var body: String?
    public var contentType: String?

    public init(method: String = "POST", url: String, body: String? = nil, contentType: String? = nil) {
        self.method = method
        self.url = url
        self.body = body
        self.contentType = contentType
    }

    public func makeRequest() throws -> URLRequest {
        guard let u = URL(string: url), u.scheme != nil, u.host() != nil else { throw PlaybackError.badURL(url) }
        var request = URLRequest(url: u)
        request.httpMethod = method.uppercased()
        if let body, !body.isEmpty {
            request.httpBody = Data(body.utf8)
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

extension HTTPClient {
    /// Performs the spec and fails on a non-2xx status, which is what every caller here wants.
    public func perform(_ spec: HTTPRequestSpec) async throws {
        let (_, response) = try await perform(spec.makeRequest())
        guard (200..<300).contains(response.statusCode) else { throw PlaybackError.httpStatus(response.statusCode) }
    }
}
