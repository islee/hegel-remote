// HegelRemoteApp.swift: app entry for iOS and macOS.
//
// Purpose: create the shared `SettingsStore` and `AmpController`, hand them to the views through the
//   environment, and wire the app lifecycle (connect on foreground, drop on background on iOS). On macOS it
//   also declares the menu bar extra (volume readout + popover) and a Settings scene.
// Context: thin by design; all logic lives in the HegelRemoteCore package target. Fonts are registered here once.
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

@main
struct HegelRemoteApp: App {
    @State private var settings: SettingsStore
    @State private var controller: AmpController
    @State private var iconApplier: AppIconApplier
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerBundledFonts()
        let settings = SettingsStore.shared
        _settings = State(initialValue: settings)
        _controller = State(initialValue: AmpController(settings: settings))
        _iconApplier = State(initialValue: AppIconApplier(settings: settings))
    }

    var body: some Scene {
        mainWindow
        #if os(macOS)
        // Menu bar extra: the volume readout as the label, the compact remote as a popover.
        MenuBarExtra {
            MenuBarView()
                .environment(settings)
                .environment(controller)
                .environment(iconApplier)
        } label: {
            Text(controller.displayVolume.map(String.init) ?? "–")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(controller)
                .environment(iconApplier)
                .followsTheme()
                .frame(minWidth: 480, minHeight: 520)
        }
        #endif
    }

    private var root: some View {
        RootView()
            .environment(settings)
            .environment(controller)
            .environment(iconApplier)
            // Apply on launch and whenever the choice (or, on the Mac, the appearance setting) changes.
            .onChange(of: settings.effectiveIconChoice, initial: true) { iconApplier.apply() }
            .onChange(of: settings.appearance) { iconApplier.apply() }
    }

    private func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            controller.appDidBecomeActive()
        case .background:
            #if os(iOS)
            controller.appDidEnterBackground()
            #endif
        default:
            break
        }
    }

    #if os(macOS)
    private var mainWindow: some Scene {
        WindowGroup {
            root.frame(minWidth: 380, idealWidth: 400, minHeight: 700, idealHeight: 820)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in scenePhaseChanged(phase) }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 820)
    }
    #else
    private var mainWindow: some Scene {
        WindowGroup { root }
            .onChange(of: scenePhase, initial: true) { _, phase in scenePhaseChanged(phase) }
    }
    #endif
}
