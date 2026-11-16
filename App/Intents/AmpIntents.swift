// AmpIntents.swift: Siri / Shortcuts intents. Each one is a thin wrapper over `IntentSupport.perform`.
//
// Purpose: power on/off/toggle, set volume, volume up/down, mute on/off, switch input (by the user's input
//   name through `AmpInputEntity`). They run inside the app process without the UI (App Intents launch the
//   app in the background), open their own short-lived connection, wait for the amp's reply and speak it.
// Context: no SiriKit entitlement needed; works with free signing. Nothing here knows the protocol; the
//   mapping is `AmpAction`.
// Dependencies: AppIntents, Core.
import HegelRemoteCore
import AppIntents
import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAmpConfigured
    case unreachable(String)
    case noReply
    case unknownInput(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAmpConfigured: "No amplifier is set up yet. Open hegel-remote and add one."
        case .unreachable(let detail): "I could not reach the amplifier (\(detail))."
        case .noReply: "The amplifier did not answer."
        case .unknownInput(let name): "There is no input called \(name)."
        }
    }
}

enum IntentSupport {
    /// Runs one action against the saved amp and returns the sentence to speak.
    @MainActor
    static func perform(_ action: AmpAction) async throws -> String {
        let settings = SettingsStore.shared
        guard let address = settings.ampAddress else { throw IntentError.noAmpConfigured }
        let inputName: @Sendable (Int) -> String? = { [names = Dictionary(uniqueKeysWithValues: settings.inputs.map { ($0.number, $0.name) })] in names[$0] }
        do {
            return try await AmpSession.run(address) { client in
                let event = try await AmpActionRunner.perform(action, on: client)
                return AmpActionRunner.describe(event, inputName: inputName)
            }
        } catch AmpActionError.unreachable(let detail) {
            throw IntentError.unreachable(detail)
        } catch AmpActionError.noReply {
            throw IntentError.noReply
        }
    }
}

struct TurnAmpOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn amplifier on"
    static let description = IntentDescription("Powers the Hegel amplifier on.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.power(true)))")
    }
}

struct TurnAmpOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn amplifier off"
    static let description = IntentDescription("Puts the Hegel amplifier in standby.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.power(false)))")
    }
}

struct ToggleAmpPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle amplifier power"
    static let description = IntentDescription("Switches the Hegel amplifier between on and standby.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.togglePower))")
    }
}

struct SetAmpVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set amplifier volume"
    static let description = IntentDescription("Sets the Hegel amplifier volume (0-100).")

    @Parameter(title: "Volume", inclusiveRange: (0, 100))
    var volume: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set amplifier volume to \(\.$volume)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.setVolume(volume)))")
    }
}

struct AmpVolumeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Amplifier volume up"
    static let description = IntentDescription("Raises the Hegel amplifier volume by one step.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.volumeUp))")
    }
}

struct AmpVolumeDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Amplifier volume down"
    static let description = IntentDescription("Lowers the Hegel amplifier volume by one step.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.volumeDown))")
    }
}

struct MuteAmpIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute amplifier"
    static let description = IntentDescription("Mutes the Hegel amplifier.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.mute(true)))")
    }
}

struct UnmuteAmpIntent: AppIntent {
    static let title: LocalizedStringResource = "Unmute amplifier"
    static let description = IntentDescription("Unmutes the Hegel amplifier.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.mute(false)))")
    }
}

struct SwitchAmpInputIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch amplifier input"
    static let description = IntentDescription("Selects an input on the Hegel amplifier by its name.")

    @Parameter(title: "Input")
    var input: AmpInputEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch amplifier to \(\.$input)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await IntentSupport.perform(.selectInput(input.id)))")
    }
}
