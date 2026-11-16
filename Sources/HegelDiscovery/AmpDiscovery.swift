// AmpDiscovery.swift: find Hegel amps on the LAN.
//
// Purpose: browse `_raop._tcp` and `_airplay._tcp`, keep services whose name matches a Hegel model,
//   resolve each to an IPv4 host, and confirm by connecting to the control port and getting a `-p.` reply.
// Context: Apple-only (NWBrowser). Only confirmed amps are yielded; the stream ends after `timeout`.
//   Confirmation sends read-only queries (`-p.?` etc.) and no keepalive.
// Dependencies: Network, HegelProtocol, HegelClient.
import Foundation
import HegelClient
import HegelProtocol
import Network

public struct DiscoveredAmp: Sendable, Equatable, Hashable {
    public var name: String
    public var model: AmpModel?
    public var serviceType: String
    public var host: String
    public var port: UInt16
    public var state: AmpState
}

public enum AmpDiscovery {
    public static let serviceTypes = ["_raop._tcp", "_airplay._tcp"]

    public static func discover(timeout: TimeInterval = 6, controlPort: UInt16 = 50001) -> AsyncStream<DiscoveredAmp> {
        AsyncStream { continuation in
            let task = Task {
                let (results, resultsContinuation) = AsyncStream.makeStream(of: NWBrowser.Result.self)
                let queue = DispatchQueue(label: "HegelKit.Discovery")
                var browsers: [NWBrowser] = []
                for type in serviceTypes {
                    let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
                    browser.browseResultsChangedHandler = { _, changes in
                        for case .added(let r) in changes { resultsContinuation.yield(r) }
                    }
                    browser.start(queue: queue)
                    browsers.append(browser)
                }
                let deadline = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    resultsContinuation.finish()
                }
                let seenNames = Seen()
                let seenHosts = Seen()
                await withTaskGroup(of: Void.self) { group in
                    for await result in results {
                        guard case .service(let name, let type, _, _) = result.endpoint,
                              let model = HegelNameMatcher.model(forServiceName: name),
                              seenNames.insert(name) else { continue }
                        group.addTask {
                            guard let host = await resolveIPv4(result.endpoint, timeout: 3),
                                  seenHosts.insert(host),
                                  let state = await AmpClient.probe(host: host, port: controlPort, timeout: 3)
                            else { return }
                            continuation.yield(DiscoveredAmp(
                                name: name, model: model, serviceType: type, host: host,
                                port: controlPort, state: state))
                        }
                    }
                }
                deadline.cancel()
                for b in browsers { b.cancel() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Insert-once set shared across the discovery child tasks.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var items = Set<String>()
    func insert(_ s: String) -> Bool { lock.withLock { items.insert(s).inserted } }
}

/// One-shot continuation guard: callbacks may fire repeatedly, the continuation must resume once.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    init(_ c: CheckedContinuation<String?, Never>) { continuation = c }
    func resume(_ value: String?) {
        let c = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(returning: value)
    }
}

/// Resolves a Bonjour service endpoint to its IPv4 address by connecting to it and reading the path's remote endpoint.
private func resolveIPv4(_ endpoint: NWEndpoint, timeout: TimeInterval) async -> String? {
    let params = NWParameters.tcp
    if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
    let connection = NWConnection(to: endpoint, using: params)
    let queue = DispatchQueue(label: "HegelKit.Resolve")
    let host: String? = await withCheckedContinuation { c in
        let once = Once(c)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(let h, _)? = connection.currentPath?.remoteEndpoint {
                    once.resume("\(h)".split(separator: "%").first.map(String.init))
                } else {
                    once.resume(nil)
                }
            case .failed, .cancelled:
                once.resume(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
    }
    connection.cancel()
    return host
}

extension AmpClient {
    /// Connects, waits for the first state replies and disconnects. Returns the state if the peer answered
    /// the `-p.?` query (the confirmation that it is an amp), else nil. Sends read-only queries only.
    public static func probe(host: String, port: UInt16 = 50001, timeout: TimeInterval = 3) async -> AmpState? {
        var config = AmpClientConfiguration()
        config.connectTimeout = timeout
        config.keepaliveInterval = nil
        config.autoReconnect = false
        let client = AmpClient(host: host, port: port, configuration: config)
        do { try await client.connect() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while await client.state.power == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        // Brief grace so the other three replies land too.
        await client.waitForInitialState(timeout: 0.3)
        let state = await client.state
        await client.disconnect()
        return state.power == nil ? nil : state
    }
}
