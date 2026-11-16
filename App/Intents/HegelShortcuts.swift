// HegelShortcuts.swift: App Shortcuts: the Siri phrases that work with no setup in the Shortcuts app.
//
// Purpose: "Turn off the amp in hegel-remote" style phrases for every intent. `applicationName` is the
//   bundle display name (hegel-remote). Input names are refreshed with `updateAppShortcutParameters()` after
//   the user edits inputs (SettingsView.onDisappear).
// Dependencies: AppIntents.
import HegelRemoteCore
import AppIntents

struct HegelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnAmpOnIntent(),
            phrases: ["Turn on the amp in \(.applicationName)", "Turn on the amplifier in \(.applicationName)"],
            shortTitle: "Amp on", systemImageName: "power")
        AppShortcut(
            intent: TurnAmpOffIntent(),
            phrases: ["Turn off the amp in \(.applicationName)", "Turn off the amplifier in \(.applicationName)"],
            shortTitle: "Amp off", systemImageName: "power")
        AppShortcut(
            intent: ToggleAmpPowerIntent(),
            phrases: ["Toggle the amp in \(.applicationName)"],
            shortTitle: "Toggle amp", systemImageName: "power.circle")
        AppShortcut(
            intent: SetAmpVolumeIntent(),
            // An Int parameter cannot appear in a phrase (only AppEnum/AppEntity can); Siri asks for the number.
            phrases: ["Set the amp volume in \(.applicationName)"],
            shortTitle: "Set volume", systemImageName: "speaker.wave.2")
        AppShortcut(
            intent: AmpVolumeUpIntent(),
            phrases: ["Amp volume up in \(.applicationName)", "Turn the amp up in \(.applicationName)"],
            shortTitle: "Volume up", systemImageName: "speaker.plus")
        AppShortcut(
            intent: AmpVolumeDownIntent(),
            phrases: ["Amp volume down in \(.applicationName)", "Turn the amp down in \(.applicationName)"],
            shortTitle: "Volume down", systemImageName: "speaker.minus")
        AppShortcut(
            intent: MuteAmpIntent(),
            phrases: ["Mute the amp in \(.applicationName)"],
            shortTitle: "Mute", systemImageName: "speaker.slash")
        AppShortcut(
            intent: UnmuteAmpIntent(),
            phrases: ["Unmute the amp in \(.applicationName)"],
            shortTitle: "Unmute", systemImageName: "speaker.wave.2")
        AppShortcut(
            intent: SwitchAmpInputIntent(),
            phrases: ["Switch the amp to \(\.$input) in \(.applicationName)", "Switch the amp input in \(.applicationName)"],
            shortTitle: "Switch input", systemImageName: "rectangle.connected.to.line.below")
    }
}
