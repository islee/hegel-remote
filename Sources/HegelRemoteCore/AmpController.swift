// AmpController.swift: the app's one live connection to the amp, as an observable main-actor object.
//
// Purpose: the view models' core. Owns an `AmpClient`, folds its event stream into observable state,
//   coalesces fast volume changes (wheel detents, slider drags) into paced `-v.<n>` writes, resolves the
//   playback driver for the current input, and runs custom buttons. Views only call methods and read
//   properties; nothing here imports SwiftUI, so the same object can back widgets or a Watch app later.
// Context: `AmpClient` reconnects by itself with backoff and re-queries state; the controller only maps its
//   connection events to a `Phase` the UI can show. On iOS the connection is dropped on background and reopened
//   on foreground (a suspended socket is not trustworthy). The amp broadcasts every change, so state shown here
//   follows the front panel and other apps too.
// Dependencies: HegelProtocol, HegelClient, SettingsStore, AmpActions, Playback, CustomButton.
import Foundation
import HegelClient
import HegelProtocol

@MainActor @Observable
public final class AmpController {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case unreachable(String)

        public var label: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .unreachable: "Unreachable, retrying…"
            }
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var amp = AmpState()
    /// Volume the user asked for and the amp has not confirmed yet; views show it over `amp.volume`.
    public private(set) var pendingVolume: Int?
    public private(set) var playbackState: PlaybackState?
    /// Last failure worth a toast; views clear it.
    public var lastError: String?

    public let settings: SettingsStore
    private let http: any HTTPClient
    private let makeClient: @Sendable (AmpAddress) -> AmpClient

    private var client: AmpClient?
    private var eventTask: Task<Void, Never>?
    private var volumeFlushTask: Task<Void, Never>?
    private var playbackPollTask: Task<Void, Never>?

    /// Seconds between playback state polls while a state-reporting driver is active.
    public var playbackPollInterval: Duration = .seconds(5)

    public init(settings: SettingsStore, http: any HTTPClient = URLSessionHTTPClient(),
                makeClient: @escaping @Sendable (AmpAddress) -> AmpClient = { AmpClient(host: $0.host, port: $0.port) }) {
        self.settings = settings
        self.http = http
        self.makeClient = makeClient
    }

    // MARK: Derived state for views

    public var isConnected: Bool { phase == .connected }
    public var displayVolume: Int? { pendingVolume ?? amp.volume }
    public var inputs: [InputItem] { settings.enabledInputs }
    public var currentInput: InputItem? { amp.input.flatMap { settings.input(number: $0) } }
    public var capabilities: ModelCapabilities { settings.capabilities }

    /// Driver for the current input's playback target. Re-resolved on input change and `settingsDidChange()`.
    public private(set) var playbackDriver: any PlaybackDriver = UnavailablePlaybackDriver(reason: PlaybackDrivers.noTargetReason)
    private var playbackDriverTarget: PlaybackTarget?

    public var playbackUnavailableReason: String? { playbackDriver.unavailableReason }

    /// Call after the user edited inputs or playback targets in settings.
    public func settingsDidChange() {
        updatePlaybackDriver(force: true)
    }

    private func updatePlaybackDriver(force: Bool = false) {
        let target = currentInput?.playbackTarget
        guard force || target != playbackDriverTarget else { return }
        playbackDriverTarget = target
        playbackDriver = PlaybackDrivers.make(target, http: http, clientID: settings.plexClientID)
        restartPlaybackPolling(for: playbackDriver)
    }

    // MARK: Lifecycle

    /// Opens the connection to the remembered amp (no-op when already open or no amp is saved). Returns at
    /// once; `phase` reports progress. The client keeps retrying with backoff until `disconnect()`.
    public func connect() {
        guard client == nil, let address = settings.ampAddress else { return }
        let c = makeClient(address)
        client = c
        phase = .connecting
        // Subscribe before connecting so the first `.connecting` / `.ready` is not missed.
        let events = c.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
        Task { try? await c.connect(waitForReady: false) }
    }

    public func disconnect() {
        eventTask?.cancel()
        eventTask = nil
        volumeFlushTask?.cancel()
        volumeFlushTask = nil
        stopPlaybackPolling()
        if let c = client { Task { await c.disconnect() } }
        client = nil
        pendingVolume = nil
        phase = .idle
    }

    /// Call when the amp address changed (setup, settings): drops the old connection and opens the new one.
    public func reconnect() {
        disconnect()
        amp = AmpState()
        connect()
    }

    public func appDidBecomeActive() {
        if client == nil { connect() } else { Task { [client] in try? await client?.requestState() } }
    }

    /// iOS only: a socket suspended with the app is not trustworthy, so drop it and reopen on foreground.
    public func appDidEnterBackground() {
        disconnect()
    }

    private func handle(_ event: AmpEvent) {
        switch event {
        case .connection(let status):
            switch status {
            case .connecting:
                if phase == .idle { phase = .connecting }
            case .ready:
                phase = .connected
                updatePlaybackDriver()
            case .waiting(let detail):
                phase = .unreachable(detail)
            case .failed(let reason):
                phase = .unreachable(reason)
            case .disconnected:
                phase = .idle
            }
        default:
            let before = amp.input
            amp.apply(event)
            if amp.input != before { updatePlaybackDriver() }
        }
    }

    // MARK: Amp commands

    /// Fire-and-forget for UI buttons: errors surface in `lastError`.
    public func perform(_ action: AmpAction) {
        guard let client else { lastError = "Not connected."; return }
        Task { [weak self] in
            do { _ = try await AmpActionRunner.perform(action, on: client) } catch { self?.report(error) }
        }
    }

    public func togglePower() { perform(.togglePower) }
    public func setPower(_ on: Bool) { perform(.power(on)) }
    public func toggleMute() { perform(.toggleMute) }
    public func selectInput(_ number: Int) { perform(.selectInput(number)) }

    public func selectNextInput() {
        if let next = InputCatalog.next(after: amp.input, model: settings.model, settings: settings.inputSettings) {
            selectInput(next.number)
        }
    }

    /// One wheel detent or a Vol -/+ press: moves the target by `delta` steps from the last known value.
    public func nudgeVolume(by delta: Int) {
        guard let base = displayVolume else { return }
        setVolume(base + delta)
    }

    /// Slider or preset: sets the target. Rapid calls coalesce into one paced write per change.
    public func setVolume(_ value: Int) {
        guard client != nil else { return }
        let range = capabilities.volumeRange
        pendingVolume = min(range.upperBound, max(range.lowerBound, value))
        if volumeFlushTask == nil { volumeFlushTask = Task { await flushVolume() } }
    }

    /// Sends the latest target whenever it changes, then waits (briefly) for the amp to confirm before clearing
    /// the pending value, so the readout never jumps back to a stale number mid-turn.
    private func flushVolume() async {
        defer { volumeFlushTask = nil }
        var sent: Int?
        var settleDeadline: ContinuousClock.Instant?
        while let target = pendingVolume, !Task.isCancelled {
            if target != sent {
                sent = target
                settleDeadline = nil
                guard let client else { break }
                do { try await client.setVolume(target) } catch { report(error); break }
                continue
            }
            if amp.volume == target { break }
            let deadline = settleDeadline ?? ContinuousClock.now.advanced(by: .seconds(1))
            settleDeadline = deadline
            if ContinuousClock.now >= deadline { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        pendingVolume = nil
    }

    // MARK: Playback

    public func playback(_ command: PlaybackCommand) {
        let driver = playbackDriver
        Task { [weak self] in
            do {
                try await driver.send(command)
                if driver.reportsState {
                    try? await Task.sleep(for: .milliseconds(400))
                    self?.refreshPlayback()
                }
            } catch { self?.report(error) }
        }
    }

    public func refreshPlayback() {
        let driver = playbackDriver
        guard driver.reportsState else { playbackState = nil; return }
        Task { [weak self] in
            let state = try? await driver.poll()
            self?.playbackState = state
        }
    }

    private func restartPlaybackPolling(for driver: any PlaybackDriver) {
        stopPlaybackPolling()
        guard driver.reportsState else { playbackState = nil; return }
        let interval = playbackPollInterval
        playbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let state = try? await driver.poll()
                guard let self, !Task.isCancelled else { return }
                self.playbackState = state
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopPlaybackPolling() {
        playbackPollTask?.cancel()
        playbackPollTask = nil
    }

    // MARK: Custom buttons

    public func run(_ button: CustomButton) {
        let client = self.client
        let http = self.http
        Task { [weak self] in
            do { try await CustomButtonRunner.run(button, amp: client, http: http) } catch { self?.report(error) }
        }
    }

    private func report(_ error: Error) {
        lastError = Self.message(for: error)
    }

    static func message(for error: Error) -> String {
        switch error {
        case AmpActionError.noReply(let a): "The amplifier did not answer (\(a.label(inputName: { _ in nil })))."
        case AmpActionError.unreachable(let s): "Amplifier unreachable: \(s)"
        case AmpActionError.noAmpConfigured: "No amplifier set up."
        case AmpClientError.notConnected: "Not connected."
        case PlaybackError.unavailable(let r): r
        case PlaybackError.httpStatus(let code): "The device answered HTTP \(code)."
        case PlaybackError.badURL(let u): "Bad URL: \(u)"
        case CustomButtonError.noConnection: "Not connected to the amplifier."
        default: error.localizedDescription
        }
    }
}
