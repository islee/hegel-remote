// ReadoutText.swift: what the dot-matrix readout says for a given connection and amp state.
//
// Purpose: pure mapping, shared by the iPhone dial, the Mac window and the menu bar popover, and unit-tested.
// Dependencies: AmpController.Phase.
import Foundation

public struct ReadoutText: Equatable, Sendable {
    public var volume: String
    public var source: String

    public init(volume: String, source: String) {
        self.volume = volume
        self.source = source
    }

    @MainActor
    public init(controller: AmpController, settings: SettingsStore) {
        self.init(phase: controller.phase, power: controller.amp.power, mute: controller.amp.mute,
                  volume: controller.displayVolume,
                  inputName: controller.currentInput?.name ?? controller.amp.input.map { "INPUT \($0)" })
    }

    public init(phase: AmpController.Phase, power: Bool?, mute: Bool?, volume: Int?, inputName: String?) {
        switch phase {
        case .connected:
            if power == false {
                self.init(volume: "--", source: "STANDBY")
            } else if mute == true {
                self.init(volume: volume.map(String.init) ?? "--", source: "MUTE")
            } else {
                self.init(volume: volume.map(String.init) ?? "--", source: inputName?.uppercased() ?? "")
            }
        case .connecting:
            self.init(volume: "--", source: "CONNECTING")
        case .unreachable:
            self.init(volume: "--", source: "NO CONNECTION")
        case .idle:
            self.init(volume: "--", source: "OFFLINE")
        }
    }
}
