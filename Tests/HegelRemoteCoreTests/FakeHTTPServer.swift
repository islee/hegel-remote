// FakeHTTPServer: minimal HTTP/1.1 server on 127.0.0.1 (ephemeral port) that records requests and answers
// with canned bodies, for driver and custom-button tests. One request per connection (Connection: close).
import Foundation
import Network

final class FakeHTTPServer: @unchecked Sendable {
    struct Request: Equatable, Sendable {
        var method: String
        var path: String          // path + query, as sent
        var headers: [String: String]
        var body: String
    }

    private let queue = DispatchQueue(label: "FakeHTTPServer")
    private var listener: NWListener!
    private var requests: [Request] = []
    private var responder: @Sendable (Request) -> (status: Int, body: String) = { _ in (200, "") }
    private(set) var port: UInt16 = 0

    var baseURL: String { "http://127.0.0.1:\(port)" }
    var received: [Request] { queue.sync { requests } }

    func respond(_ responder: @escaping @Sendable (Request) -> (status: Int, body: String)) {
        queue.sync { self.responder = responder }
    }

    static func start() async throws -> FakeHTTPServer {
        let server = FakeHTTPServer()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        server.listener = try NWListener(using: params)
        server.listener.newConnectionHandler = { conn in server.accept(conn) }
        server.port = try await withCheckedThrowingContinuation { c in
            let lock = NSLock()
            nonisolated(unsafe) var done = false
            server.listener.stateUpdateHandler = { state in
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                switch state {
                case .ready: done = true; c.resume(returning: server.listener.port?.rawValue ?? 0)
                case .failed(let e): done = true; c.resume(throwing: e)
                default: break
                }
            }
            server.listener.start(queue: server.queue)
        }
        return server
    }

    func stop() { queue.sync { listener.cancel() } }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(conn, buffer: [])
    }

    private func read(_ conn: NWConnection, buffer: [UInt8]) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer += data }
            if let request = Self.parse(buffer) {
                requests.append(request)
                let (status, body) = responder(request)
                let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: text/xml\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
            } else if error != nil || isComplete {
                conn.cancel()
            } else {
                read(conn, buffer: buffer)
            }
        }
    }

    /// Returns the request once head and (per Content-Length) body are complete. Works on bytes: Swift strings
    /// treat "\r\n" as one Character, so character offsets would misplace the body.
    private static func parse(_ bytes: [UInt8]) -> Request? {
        let separator: [UInt8] = [13, 10, 13, 10]
        guard bytes.count >= 4,
              let headEnd = (0...(bytes.count - 4)).first(where: { Array(bytes[$0..<$0 + 4]) == separator })
        else { return nil }
        let head = String(decoding: bytes[..<headEnd], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyBytes = bytes[(headEnd + 4)...]
        guard bodyBytes.count >= length else { return nil }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                       body: String(decoding: bodyBytes.prefix(length), as: UTF8.self))
    }
}
