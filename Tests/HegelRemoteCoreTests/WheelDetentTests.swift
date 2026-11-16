import Foundation
import Testing
@testable import HegelRemoteCore

@Suite struct WheelDetentTests {
    @Test func tapProducesNoStep() {
        var t = WheelDetentTracker(detentsPerRevolution: 24)
        t.begin(angle: 1.0)
        #expect(t.update(angle: 1.0) == 0)
        #expect(t.update(angle: 1.0 + t.detentAngle * 0.9) == 0)
    }

    @Test func oneDetentIsOneStepClockwiseAndBack() {
        var t = WheelDetentTracker(detentsPerRevolution: 24)
        t.begin(angle: 0)
        #expect(t.update(angle: t.detentAngle * 1.05) == 1)
        #expect(t.update(angle: t.detentAngle * 1.5) == 0)
        #expect(t.update(angle: t.detentAngle * 2.1) == 1)
        #expect(t.update(angle: -t.detentAngle * 0.2) == -2)
    }

    @Test func fullRevolutionInSmallMovesGivesExactlyTheDetentCount() {
        var t = WheelDetentTracker(detentsPerRevolution: 24)
        t.begin(angle: -.pi)
        var total = 0
        for i in 1...200 { total += t.update(angle: -.pi + 2 * .pi * Double(i) / 200) }
        #expect(total == 24)
    }

    @Test func crossingThePiSeamIsNotAFullTurn() {
        var t = WheelDetentTracker(detentsPerRevolution: 24)
        // atan2 jumps from +pi to -pi when passing the 9 o'clock position clockwise (view coordinates).
        t.begin(angle: .pi - 0.05)
        #expect(t.update(angle: -.pi + 0.05) == 0)
        #expect(t.update(angle: -.pi + 0.05 + t.detentAngle) == 1)
        t.begin(angle: -.pi + 0.05)
        #expect(t.update(angle: .pi - 0.05) == 0)
    }

    @Test func angleHelperIsClockwisePositiveInViewCoordinates() {
        let c = CGPoint(x: 100, y: 100)
        let right = WheelDetentTracker.angle(of: CGPoint(x: 200, y: 100), around: c)
        let bottom = WheelDetentTracker.angle(of: CGPoint(x: 100, y: 200), around: c)
        #expect(abs(right) < 0.0001)
        #expect(abs(bottom - .pi / 2) < 0.0001)
    }

    @Test func updateWithoutBeginStartsTracking() {
        var t = WheelDetentTracker()
        #expect(t.update(angle: 0.3) == 0)
        #expect(t.update(angle: 0.3 + t.detentAngle * 1.1) == 1)
        t.end()
        #expect(t.update(angle: 2) == 0)
    }
}

@Suite struct ReadoutTextTests {
    @Test func statesMapToReadoutWords() {
        #expect(ReadoutText(phase: .connected, power: true, mute: false, volume: 39, inputName: "Network") == ReadoutText(volume: "39", source: "NETWORK"))
        #expect(ReadoutText(phase: .connected, power: false, mute: false, volume: 39, inputName: "Network") == ReadoutText(volume: "--", source: "STANDBY"))
        #expect(ReadoutText(phase: .connected, power: true, mute: true, volume: 39, inputName: "Network") == ReadoutText(volume: "39", source: "MUTE"))
        #expect(ReadoutText(phase: .connected, power: nil, mute: nil, volume: nil, inputName: nil) == ReadoutText(volume: "--", source: ""))
        #expect(ReadoutText(phase: .connecting, power: nil, mute: nil, volume: nil, inputName: nil).source == "CONNECTING")
        #expect(ReadoutText(phase: .unreachable("x"), power: true, mute: false, volume: 10, inputName: "A").source == "NO CONNECTION")
        #expect(ReadoutText(phase: .idle, power: nil, mute: nil, volume: nil, inputName: nil).source == "OFFLINE")
    }
}
