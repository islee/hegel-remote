// Transport.swift: thin NWConnection wrapper that exposes a connection as an AsyncStream.
//
// Purpose: keep Network.framework callbacks out of AmpClient. One Transport = one TCP connection
//   attempt; it is never reused after the stream finishes.
// Context: Apple-only (Network.framework). Internal to HegelClient.
// Dependencies: Network, Foundation.
import Foundation
import Network

enum TransportEvent: Sendable, Equatable {
    case ready
    case waiting(String)
    case failed(String)
    case data([UInt8])
    /// The peer closed the connection (EOF).
    case closed
}

final class Transport: @unchecked Sendable {
    let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "HegelKit.Transport")

    init(host: String, port: UInt16) {
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 50001, using: params)
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                continuation.yield(.ready)
                receiveNext()
            case .waiting(let error):
                continuation.yield(.waiting("\(error)"))
            case .failed(let error):
                continuation.yield(.failed("\(error)"))
                continuation.finish()
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { continuation.yield(.data([UInt8](data))) }
            if let error {
                continuation.yield(.failed("\(error)"))
                continuation.finish()
                connection.cancel()
            } else if isComplete {
                continuation.yield(.closed)
                continuation.finish()
                connection.cancel()
            } else {
                receiveNext()
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    /// Tears the connection down. With a reason, the stream first reports `.failed(reason)`.
    func cancel(reason: String? = nil) {
        if let reason { continuation.yield(.failed(reason)) }
        continuation.finish()
        connection.cancel()
    }
}
