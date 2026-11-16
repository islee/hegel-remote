// SettingsView.swift: amplifier, appearance, inputs, custom buttons, skins, about.
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
    @Environment(\.dismiss) private var dismiss
    @State private var showSetup = false
    @State private var skinJSON = ""
    @State private var skinImportError: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                amplifierSection
                Section("Appearance") {
                    Picker("Skin", selection: $settings.skinID) {
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
                }
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
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #endif
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
            settings.skinID = skin.id
            skinJSON = ""
            skinImportError = nil
        } catch {
            skinImportError = "Not a valid skin: \(error.localizedDescription)"
        }
    }

    private func removeSkin(_ skin: Skin) {
        settings.userSkins.removeAll { $0.id == skin.id }
        if settings.skinID == skin.id { settings.skinID = Skin.defaultID }
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
