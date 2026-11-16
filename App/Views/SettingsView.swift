// SettingsView.swift: amplifier, appearance and skins, app icon, inputs, custom buttons, about.
//
// Purpose: every persisted choice in one Form. Sub-editors (inputs, custom buttons) are their own files.
// Context: on iOS this is a sheet; on macOS also the Settings scene. On dismiss MainView calls
//   `controller.settingsDidChange()` so playback targets re-resolve.
// Dependencies: SwiftUI, AppIntents (App Shortcut parameter refresh), Core.
import HegelRemoteCore
import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    @Environment(AppIconApplier.self) private var iconApplier
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showSetup = false
    @State private var skinJSON = ""
    @State private var skinImportError: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                amplifierSection
                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Light skin", selection: $settings.skinPairing.lightID) {
                        ForEach(settings.allSkins) { skin in Text(skin.name).tag(skin.id) }
                    }
                    Picker("Dark skin", selection: $settings.skinPairing.darkID) {
                        ForEach(settings.allSkins) { skin in Text(skin.name).tag(skin.id) }
                    }
                    Picker("Volume control", selection: Binding(
                        get: { settings.volumeControlOverride?.rawValue ?? "skin" },
                        set: { settings.volumeControlOverride = VolumeControlKind(rawValue: $0) })
                    ) {
                        Text("Skin default (\(settings.skin.volumeControl == .wheel ? "wheel" : "slider"))").tag("skin")
                        Text("Click wheel").tag(VolumeControlKind.wheel.rawValue)
                        Text("Slider").tag(VolumeControlKind.slider.rawValue)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Appearance follows the system unless you pick Light or Dark. Each appearance has its own skin; any skin can go in either slot.")
                }
                .id("appearance")
                iconSection
                Section {
                    NavigationLink("Inputs") { InputsEditor() }
                    NavigationLink("Custom buttons") { CustomButtonsEditor() }
                } footer: {
                    Text("Inputs: rename, enable/disable, and map a playback target (Plexamp\(PlaybackTarget.Kind.availableHere.contains(.macMediaKeys) ? ", Mac media keys" : "")) for the Prev / Play / Next row. Custom buttons: a label plus an ordered list of amp commands and HTTP requests.")
                }
                skinsSection
                Section("About") {
                    LabeledContent("Readout font", value: FontRegistry.isDotoAvailable ? "Doto (SIL OFL 1.1)" : "System monospaced")
                    Text("Unofficial. Not affiliated with Hegel Music Systems AS. Model names describe compatibility only.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            // `-scrollToAppIcon YES` (Docs/screenshots/make.sh) scrolls so Appearance and App icon are in view.
            .task {
                if UserDefaults.standard.bool(forKey: "scrollToAppIcon") {
                    try? await Task.sleep(for: .milliseconds(500))
                    proxy.scrollTo("appearance", anchor: UnitPoint(x: 0.5, y: -0.05))
                }
            }
            }
            .navigationTitle("Settings")
            .toolbar {
                // WHY on both platforms: on the Mac this view is also a sheet (gear button), and without a Done
                // button Esc was the only way to close it (owner report, 2026-11-16).
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showSetup) {
                SetupView().environment(settings).environment(controller)
            }
        }
        .tint(settings.skin.accent)
        .onDisappear {
            controller.settingsDidChange()
            HegelShortcuts.updateAppShortcutParameters()
        }
    }

    private var amplifierSection: some View {
        @Bindable var settings = settings
        return Section {
            if let address = settings.ampAddress {
                LabeledContent("Address", value: address.displayHost)
                Picker("Model", selection: Binding(
                    get: { address.modelID },
                    set: { settings.ampAddress?.modelID = $0 })
                ) {
                    ForEach(ModelCapabilities.all, id: \.modelID) { cap in Text(cap.pickerLabel).tag(cap.modelID) }
                }
                TextField("Name", text: Binding(
                    get: { address.name ?? "" },
                    set: { settings.ampAddress?.name = $0.isEmpty ? nil : $0 }))
                Button("Change amplifier…") { showSetup = true }
                Button("Forget amplifier", role: .destructive) {
                    controller.disconnect()
                    settings.forgetAmp()
                    dismiss()
                }
            } else {
                Button("Set up amplifier…") { showSetup = true }
            }
        } header: {
            Text("Amplifier")
        } footer: {
            Text(settings.capabilities.notes)
        }
    }

    private var iconSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Match the amplifier model", isOn: $settings.iconFollowsModel)
            ForEach(AppIcons.choices, id: \.self) { choice in
                Button {
                    // Picking an icon by hand stops it following the model.
                    settings.iconFollowsModel = false
                    settings.iconChoice = choice
                } label: {
                    HStack(spacing: 12) {
                        Image(choice.dockImageName(dark: colorScheme == .dark))
                            .resizable().scaledToFit().frame(width: 40, height: 40)
                        Text(choice.label)
                        Spacer()
                        if settings.effectiveIconChoice == choice {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let error = iconApplier.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("App icon")
        } footer: {
            #if os(macOS)
            Text("The Dock shows the chosen icon while the app runs. The Finder and the Dock show the default icon when it is not running.")
            #else
            Text("iOS confirms each icon change with a system alert. The default icon also follows light, dark and tinted home screens.")
            #endif
        }
    }

    private var skinsSection: some View {
        Section {
            ForEach(settings.userSkins) { skin in
                HStack {
                    Text(skin.name)
                    Spacer()
                    Text(skin.id).font(.footnote).foregroundStyle(.secondary)
                }
                .swipeActions { Button("Delete", role: .destructive) { removeSkin(skin) } }
                .contextMenu { Button("Delete", role: .destructive) { removeSkin(skin) } }
            }
            TextField("Paste a skin JSON here", text: $skinJSON, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
            if let skinImportError { Text(skinImportError).font(.footnote).foregroundStyle(.red) }
            Button("Add skin from JSON") { importSkin() }
                .disabled(skinJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Copy current skin as JSON") { copyCurrentSkin() }
        } header: {
            Text("Skins")
        } footer: {
            Text("A skin is data: colours, readout font and volume control. Copy the current one, edit it, paste it back. Loading skin files is planned.")
        }
    }

    private func importSkin() {
        do {
            let skin = try settings.addUserSkin(json: Data(skinJSON.utf8))
            // Use the imported skin in the slot that is showing now, so the paste has a visible effect.
            if settings.skin.isDark { settings.skinPairing.darkID = skin.id } else { settings.skinPairing.lightID = skin.id }
            skinJSON = ""
            skinImportError = nil
        } catch {
            skinImportError = "Not a valid skin: \(error.localizedDescription)"
        }
    }

    private func removeSkin(_ skin: Skin) {
        settings.userSkins.removeAll { $0.id == skin.id }
        let pairing = settings.skinPairing
        if pairing.lightID == skin.id { settings.skinPairing.lightID = SkinPairing.default.lightID }
        if pairing.darkID == skin.id { settings.skinPairing.darkID = SkinPairing.default.darkID }
    }

    private func copyCurrentSkin() {
        guard let data = try? settings.skin.encodeJSON(), let text = String(data: data, encoding: .utf8) else { return }
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        skinJSON = text
    }
}
