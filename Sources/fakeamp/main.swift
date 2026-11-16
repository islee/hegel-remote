// fakeamp: run the FakeAmp emulator as a process, for developing the app without touching the real amplifier.
//
// Purpose: `swift run fakeamp` listens on 127.0.0.1:50001 (the H590's control port) and behaves like an H590,
//   including broadcasting every state change to all connected clients. Enter 127.0.0.1 in the app's manual
//   setup (the iOS simulator shares the Mac's loopback interface), or pass `--advertise` so Bonjour discovery
//   finds it as "FAKEAMP@H590".
// Context: development only. `--advertise` registers a `_raop._tcp` service on the LAN, so other AirPlay
//   pickers on the network will list a bogus "H590" while it runs; it is off by default for that reason.
// Dependencies: HegelFakeAmp, Network.
import Foundation
import HegelFakeAmp
import Network

var port: UInt16 = 50001
var advertise = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--port":
        guard let next = args.popFirst(), let p = UInt16(next) else { fail("--port needs a number") }
        port = p
    case "--advertise":
        advertise = true
    case "-h", "--help":
        print("usage: fakeamp [--port <n>] [--advertise]")
        exit(0)
    default:
        fail("unknown argument \(arg)")
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("fakeamp: \(message)\n".utf8))
    exit(2)
}

let amp: FakeAmp
do {
    amp = try await FakeAmp.start(port: port)
} catch {
    fail("cannot listen on 127.0.0.1:\(port): \(error)")
}
print("fakeamp listening on 127.0.0.1:\(amp.port) (power on, input 12, volume 33). Ctrl-C to stop.")

// WHY a separate listener: FakeAmp binds to 127.0.0.1 only, and a loopback socket cannot carry a Bonjour record.
// This listener only publishes the service; discovery resolves it to this Mac's LAN address and then connects to
// port 50001 there, which only reaches the loopback-bound FakeAmp from this same Mac. So `--advertise` serves the
// simulator and the Mac app, not an iPhone on the LAN (use manual entry there).
var bonjour: NWListener?
if advertise {
    let listener = try NWListener(using: .tcp)
    listener.service = NWListener.Service(name: "FAKEAMP@H590", type: "_raop._tcp")
    listener.newConnectionHandler = { $0.cancel() }
    listener.start(queue: .global())
    bonjour = listener
    print("advertising _raop._tcp \"FAKEAMP@H590\" (other AirPlay pickers on this LAN will see it)")
}

var lastSnapshot = amp.snapshot
while true {
    try await Task.sleep(for: .milliseconds(200))
    let snap = amp.snapshot
    if snap != lastSnapshot {
        print("state: power=\(snap.power ? 1 : 0) input=\(snap.input) volume=\(snap.volume) mute=\(snap.mute ? 1 : 0) clients=\(amp.clientCount)")
        lastSnapshot = snap
    }
}
