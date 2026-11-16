// hegelctl: command-line remote for Hegel amps (macOS). See `hegelctl --help`.
//
// Purpose: exercise HegelKit from a terminal: status, set commands, watch, discover.
// Context: no argument-parser dependency; arguments are parsed by hand. Exit code 0 ok, 1 runtime failure, 2 usage.
// Dependencies: HegelProtocol, HegelClient, HegelDiscovery.
import Dispatch
import Foundation
import HegelClient
import HegelDiscovery
import HegelProtocol

let usage = """
usage: hegelctl [--host <ip>] [--port 50001] [--json] [--no-keepalive] <command>

  status                    print power/input/volume/mute (one line, or JSON with --json)
  on | off | toggle         power
  vol <0-100> | vol up | vol down
  mute on | off | toggle
  input <n>
  watch                     stream events until Ctrl-C
  discover [seconds]        find amps on the LAN (no --host needed)

--no-keepalive skips the -r.3 reset-timer packet the client normally sends on connect and every 2 minutes.
"""

// WHY: amp replies, Bonjour names and error text come from the network; escape control characters so a device
// on the LAN can't inject terminal escape sequences into text-mode output. JSON output is escaped by JSONSerialization.
func printable(_ s: String) -> String {
    var out = ""
    for scalar in s.unicodeScalars {
        let v = scalar.value
        if v < 0x20 || (0x7F...0x9F).contains(v) {
            out += String(format: "\\x%02X", v)
        } else {
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((printable(message) + "\n").utf8))
    exit(code)
}

func line(_ s: AmpState) -> String {
    func f(_ v: Int?) -> String { v.map(String.init) ?? "?" }
    func b(_ v: Bool?, _ t: String, _ e: String) -> String { v.map { $0 ? t : e } ?? "?" }
    return "power=\(b(s.power, "on", "off")) input=\(f(s.input)) volume=\(f(s.volume)) mute=\(b(s.mute, "on", "off"))"
}

func json(_ object: [String: Any]) -> String {
    let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
}

func stateObject(_ s: AmpState) -> [String: Any] {
    [
        "power": s.power as Any? ?? NSNull(), "input": s.input as Any? ?? NSNull(),
        "volume": s.volume as Any? ?? NSNull(), "mute": s.mute as Any? ?? NSNull(),
    ]
}

func describe(_ e: AmpEvent) -> String {
    switch e {
    case .power(let on): "power=\(on ? "on" : "off")"
    case .input(let n): "input=\(n)"
    case .volume(let v): "volume=\(v)"
    case .mute(let m): "mute=\(m ? "on" : "off")"
    case .resetTimer(let m): "reset-timer=\(m.map(String.init) ?? "stopped")"
    case .error(let c): "error=\(c)"
    case .unrecognized(let raw): "unrecognized=\(printable(raw))"
    case .connection(let s): "connection=\(printable(String(describing: s)))"
    }
}

func eventObject(_ e: AmpEvent) -> [String: Any] {
    switch e {
    case .power(let on): ["event": "power", "value": on]
    case .input(let n): ["event": "input", "value": n]
    case .volume(let v): ["event": "volume", "value": v]
    case .mute(let m): ["event": "mute", "value": m]
    case .resetTimer(let m): ["event": "reset-timer", "value": m as Any? ?? NSNull()]
    case .error(let c): ["event": "error", "value": c]
    case .unrecognized(let raw): ["event": "unrecognized", "value": raw]
    case .connection(let s): ["event": "connection", "value": "\(s)"]
    }
}

/// First event matching `predicate` within `timeout` seconds, else nil.
func nextEvent(_ stream: AsyncStream<AmpEvent>, timeout: TimeInterval,
               where predicate: @escaping @Sendable (AmpEvent) -> Bool) async -> AmpEvent? {
    await withTaskGroup(of: AmpEvent?.self) { group in
        group.addTask {
            for await e in stream where predicate(e) { return e }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: Arguments

var args = Array(CommandLine.arguments.dropFirst())
var host: String?
var port: UInt16 = 50001
var asJSON = false
var keepalive = true
var rest: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--host": host = args.isEmpty ? nil : args.removeFirst()
    case "--port":
        guard !args.isEmpty, let p = UInt16(args.removeFirst()) else { fail("--port needs 0-65535\n" + usage, code: 2) }
        port = p
    case "--json": asJSON = true
    case "--no-keepalive": keepalive = false
    case "-h", "--help": print(usage); exit(0)
    default: rest.append(a)
    }
}
guard let verb = rest.first else { fail(usage, code: 2) }
let operands = Array(rest.dropFirst())

/// What a set command sends, and which event kind confirms it.
func plan() -> (Command, @Sendable (AmpEvent) -> Bool)? {
    @Sendable func isPower(_ e: AmpEvent) -> Bool { if case .power = e { true } else { false } }
    @Sendable func isVolume(_ e: AmpEvent) -> Bool { if case .volume = e { true } else { false } }
    @Sendable func isMute(_ e: AmpEvent) -> Bool { if case .mute = e { true } else { false } }
    @Sendable func isInput(_ e: AmpEvent) -> Bool { if case .input = e { true } else { false } }
    switch (verb, operands.first) {
    case ("on", nil): return (.power(.on), isPower)
    case ("off", nil): return (.power(.off), isPower)
    case ("toggle", nil): return (.power(.toggle), isPower)
    case ("vol", "up"): return (.volume(.up), isVolume)
    case ("vol", "down"): return (.volume(.down), isVolume)
    case ("vol", let v?):
        guard let n = Int(v), (0...100).contains(n) else { fail("vol needs 0-100, up or down", code: 2) }
        return (.volume(.set(n)), isVolume)
    case ("mute", "on"): return (.mute(.on), isMute)
    case ("mute", "off"): return (.mute(.off), isMute)
    case ("mute", "toggle"): return (.mute(.toggle), isMute)
    case ("input", let v?):
        guard let n = Int(v), n >= 1 else { fail("input needs a number >= 1", code: 2) }
        return (.input(.set(n)), isInput)
    default: return nil
    }
}

// MARK: Run

if verb == "discover" {
    let seconds = operands.first.flatMap(TimeInterval.init) ?? 6
    var found = 0
    for await amp in AmpDiscovery.discover(timeout: seconds, controlPort: port) {
        found += 1
        if asJSON {
            print(json(["name": amp.name, "model": amp.model?.id as Any? ?? NSNull(), "host": amp.host,
                        "port": Int(amp.port), "state": stateObject(amp.state)]))
        } else {
            print(printable("\(amp.host):\(amp.port)  \(amp.model?.displayName ?? "?")  \(amp.name)  \(line(amp.state))"))
        }
    }
    if found == 0 { FileHandle.standardError.write(Data("no amps found\n".utf8)); exit(1) }
    exit(0)
}

guard let host else { fail("--host is required\n" + usage, code: 2) }
let action = plan()
guard verb == "status" || verb == "watch" || action != nil else { fail(usage, code: 2) }

var config = AmpClientConfiguration()
config.autoReconnect = (verb == "watch")
if !keepalive { config.keepaliveInterval = nil }
let client = AmpClient(host: host, port: port, configuration: config)

if verb == "watch" {
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler { exit(0) }
    sigint.resume()
    let stream = client.events
    do { try await client.connect(waitForReady: false) }
    for await e in stream { print(asJSON ? json(eventObject(e)) : describe(e)); fflush(stdout) }
    exit(0)
}

do { try await client.connect() } catch { fail("connect to \(host):\(port) failed: \(error)") }
guard await client.waitForInitialState(timeout: 3) else {
    let s = await client.state
    if s.power == nil { fail("amp did not report state") }
    // Partial state is still worth printing (e.g. the amp answered some queries only).
    print(asJSON ? json(stateObject(s)) : line(s)); exit(0)
}

if let (command, confirms) = action {
    let stream = client.events
    do { try await client.send(command) } catch { fail("send failed: \(error)") }
    guard let reply = await nextEvent(stream, timeout: 2, where: confirms) else { fail("no reply from amp") }
    if case .error(let code) = reply { fail("amp rejected the command (-e.\(code))") }
}
let final = await client.state
print(asJSON ? json(stateObject(final)) : line(final))
await client.disconnect()
exit(0)
