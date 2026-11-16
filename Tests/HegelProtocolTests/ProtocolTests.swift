import Testing
@testable import HegelProtocol

@Suite struct CommandTests {
    @Test func encodesEveryCommand() {
        let cases: [(Command, String)] = [
            (.power(.on), "-p.1\r"), (.power(.off), "-p.0\r"), (.power(.toggle), "-p.t\r"), (.power(.query), "-p.?\r"),
            (.input(.set(12)), "-i.12\r"), (.input(.query), "-i.?\r"),
            (.volume(.set(50)), "-v.50\r"), (.volume(.up), "-v.u\r"), (.volume(.down), "-v.d\r"), (.volume(.query), "-v.?\r"),
            (.mute(.on), "-m.1\r"), (.mute(.off), "-m.0\r"), (.mute(.toggle), "-m.t\r"), (.mute(.query), "-m.?\r"),
            (.resetTimer(.minutes(3)), "-r.3\r"), (.resetTimer(.stop), "-r.~\r"), (.resetTimer(.query), "-r.?\r"),
        ]
        for (command, wire) in cases { #expect(command.wire == wire) }
    }

    @Test func clampsParameters() {
        #expect(Command.volume(.set(150)).wire == "-v.100\r")
        #expect(Command.volume(.set(-4)).wire == "-v.0\r")
        #expect(Command.input(.set(0)).wire == "-i.1\r")
        #expect(Command.resetTimer(.minutes(999)).wire == "-r.255\r")
    }

    @Test func neverContainsLineFeed() {
        #expect(!Command.stateQueries.contains { $0.bytes.contains(0x0A) })
        #expect(Command.stateQueries.map(\.wire).joined() == "-p.?\r-i.?\r-v.?\r-m.?\r")
        #expect(Command.power(.on).bytes == [0x2D, 0x70, 0x2E, 0x31, 0x0D])
    }
}

@Suite struct ParseTests {
    private func event(_ s: String) -> AmpEvent {
        var f = PacketFramer()
        return f.feed(Array(s.utf8)).first ?? .unrecognized("<none>")
    }

    @Test func parsesEveryReply() {
        #expect(event("-p.1\r") == .power(true))
        #expect(event("-p.0\r") == .power(false))
        #expect(event("-i.12\r") == .input(12))
        #expect(event("-v.33\r") == .volume(33))
        #expect(event("-m.0\r") == .mute(false))
        #expect(event("-m.1\r") == .mute(true))
        #expect(event("-r.~\r") == .resetTimer(minutes: nil))
        #expect(event("-r.3\r") == .resetTimer(minutes: 3))
        #expect(event("-e.1\r") == .error(code: 1))
    }

    @Test func badParametersAreUnrecognized() {
        #expect(event("-p.x\r") == .unrecognized("-p.x"))
        #expect(event("-v.101\r") == .unrecognized("-v.101"))
        #expect(event("-z.1\r") == .unrecognized("-z.1"))
        #expect(event("hello\r") == .unrecognized("hello"))
        #expect(event("-\r") == .unrecognized("-"))
        #expect(event("-..\r") == .unrecognized("-.."))
    }

    @Test func stateFoldsEvents() {
        var s = AmpState()
        #expect(!s.isComplete)
        let first = s.apply(.power(true))
        let again = s.apply(.power(true))
        #expect(first)
        #expect(!again)
        s.apply(.input(12)); s.apply(.volume(33)); s.apply(.mute(false))
        #expect(s == AmpState(power: true, input: 12, volume: 33, mute: false))
        #expect(s.isComplete)
        let onError = s.apply(.error(code: 1))
        #expect(!onError)
    }
}

@Suite struct FramerTests {
    @Test func concatenatedReplies() {
        var f = PacketFramer()
        let events = f.feed(Array("-p.1\r-i.12\r-v.33\r-m.0\r".utf8))
        #expect(events == [.power(true), .input(12), .volume(33), .mute(false)])
        #expect(f.pendingByteCount == 0)
    }

    @Test func splitAtEveryByteBoundary() {
        let wire = Array("-p.1\r-i.12\r-v.33\r-m.0\r".utf8)
        for cut in 0...wire.count {
            var f = PacketFramer()
            let events = f.feed(wire[..<cut]) + f.feed(wire[cut...])
            #expect(events == [.power(true), .input(12), .volume(33), .mute(false)], "cut at \(cut)")
        }
    }

    @Test func byteAtATime() {
        var f = PacketFramer()
        var out: [AmpEvent] = []
        for b in "-v.33\r-e.1\r".utf8 { out += f.feed([b]) }
        #expect(out == [.volume(33), .error(code: 1)])
    }

    @Test func toleratesLineFeedAndWhitespaceNoise() {
        var f = PacketFramer()
        let events = f.feed(Array("\n-p.1\r\n\r  -v.33 \r\n\n".utf8))
        #expect(events == [.power(true), .volume(33)])
    }

    @Test func errorAndUnknownDoNotCrash() {
        var f = PacketFramer()
        let events = f.feed(Array("-e.1\r-q.9\rgarbage\r\u{0}\u{FF}\u{FE}\r".utf8))
        #expect(events.first == .error(code: 1))
        #expect(events.contains(.unrecognized("-q.9")))
        #expect(events.contains(.unrecognized("garbage")))
        #expect(events.count == 4)
    }

    @Test func feedPacketsDropsMalformed() {
        var f = PacketFramer()
        let packets = f.feedPackets(Array("-p.1\rjunk\r-v.5\r".utf8))
        #expect(packets == [Packet(command: "p", param: "1"), Packet(command: "v", param: "5")])
    }

    @Test func runawayInputIsBounded() {
        var f = PacketFramer()
        _ = f.feed(Array(repeating: UInt8(ascii: "x"), count: PacketFramer.maxPending + 1))
        #expect(f.pendingByteCount == 0)
        #expect(f.feed(Array("-p.0\r".utf8)) == [.power(false)])
    }
}

@Suite struct ModelTests {
    @Test func tables() {
        #expect(AmpModel.h590.inputs.count == 12)
        #expect(AmpModel.h590.inputName(1) == "XLR 1")
        #expect(AmpModel.h590.inputName(5) == "Analog 3")
        #expect(AmpModel.h590.inputName(11) == "USB")
        #expect(AmpModel.h590.inputName(12) == "Network")
        #expect(AmpModel.h390.inputs.count == 10)
        #expect(AmpModel.h390.inputName(1) == "XLR")
        #expect(AmpModel.h390.inputName(10) == "Network")
        #expect(AmpModel.h190.inputs.count == 9)
        #expect(AmpModel.h190.inputName(1) == "Balanced")
        #expect(AmpModel.h190.inputName(9) == "Network")
        #expect(AmpModel.h120.inputs == AmpModel.h190.inputs)
        #expect(AmpModel.h95.inputs.count == 8)
        #expect(AmpModel.h95.inputName(1) == "Analog 1")
        #expect(AmpModel.h95.inputName(8) == "Network")
        #expect(AmpModel.h95.inputName(9) == nil)
    }

    @Test func tablesAreContiguousAndLookupWorks() {
        for m in AmpModel.all {
            #expect(m.inputs.map(\.number) == Array(stride(from: 1, through: m.inputs.count, by: 1)))
        }
        #expect(AmpModel.model(id: "H590") == .h590)
        #expect(AmpModel.h590.inputNumber(named: "usb") == 11)
        #expect(Set(AmpModel.all.map(\.id)).count == AmpModel.all.count)
    }
}
