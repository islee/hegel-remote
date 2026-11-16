// CustomButton.swift: user-defined buttons as data: a label plus an ordered list of actions.
//
// Purpose: presets like "Late night: Network, volume 25", and later Home Assistant webhooks (HTTP action) or
//   anything the amp cannot do over IP. DAC-Loop on/off is one such thing: it is set only in the amp's menu
//   with the RC8 remote and the a-z probe found no IP command for it, so it is NOT offered as an amp action;
//   an IR blaster or HA webhook could do it through the HTTP action later.
// Context: actions run in order; an amp action waits for the amp's confirming reply before the next action so
//   "input, then volume" lands in that order. Pure model plus a runner over the `AmpCommanding` seam.
// Dependencies: AmpActions, HTTPClient.
import Foundation

public enum ButtonAction: Hashable, Sendable, Codable {
    case amp(AmpAction)
    case http(HTTPRequestSpec)

    public func label(inputName: (Int) -> String?) -> String {
        switch self {
        case .amp(let a): a.label(inputName: inputName)
        case .http(let spec): "\(spec.method.uppercased()) \(spec.url)"
        }
    }
}

public struct CustomButton: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var label: String
    public var actions: [ButtonAction]

    public init(id: UUID = UUID(), label: String, actions: [ButtonAction]) {
        self.id = id
        self.label = label
        self.actions = actions
    }

    /// The one preset shipped on first launch.
    public static let exampleLateNight = CustomButton(
        id: UUID(uuidString: "6F2B1D4C-0000-4000-8000-000000000001")!,
        label: "Late night · Net 25",
        actions: [.amp(.selectInput(12)), .amp(.setVolume(25))])
}

public enum CustomButtonError: Error, Equatable, Sendable {
    case noConnection
}

public enum CustomButtonRunner {
    /// Runs the button's actions in order. `amp` may be nil when no connection exists; an amp action then fails
    /// and stops the sequence. HTTP actions need no amp.
    public static func run(_ button: CustomButton, amp: (any AmpCommanding)?, http: any HTTPClient) async throws {
        for action in button.actions {
            switch action {
            case .amp(let ampAction):
                guard let amp else { throw CustomButtonError.noConnection }
                _ = try await AmpActionRunner.perform(ampAction, on: amp)
            case .http(let spec):
                try await http.perform(spec)
            }
        }
    }
}
