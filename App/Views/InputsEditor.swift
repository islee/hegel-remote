// InputsEditor.swift: per-input settings: enabled, name, playback target.
//
// Purpose: edits `InputSetting` rows through SettingsStore.update(_:). The playback target editor offers only
//   the kinds this platform can drive (PlaybackTarget.Kind.availableHere).
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct InputsEditor: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(settings.inputs) { item in
                    NavigationLink {
                        InputDetailEditor(item: item)
                    } label: {
                        HStack {
                            Text("\(item.number)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if item.isRenamed || item.playbackTarget != nil {
                                    Text([item.isRenamed ? item.defaultName : nil, item.playbackTarget?.caption]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(
                                get: { item.isEnabled },
                                set: { settings.update(setting(for: item, isEnabled: $0)) }))
                                .labelsHidden()
                        }
                    }
                }
            } footer: {
                Text("Disabled inputs are hidden from the remote and from Siri. \(settings.model.displayName): \(settings.inputs.count) inputs.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inputs")
    }

    private func setting(for item: InputItem, isEnabled: Bool) -> InputSetting {
        InputSetting(number: item.number, name: item.isRenamed ? item.name : nil, isEnabled: isEnabled,
                     playbackTarget: item.playbackTarget)
    }
}

struct InputDetailEditor: View {
    @Environment(SettingsStore.self) private var settings
    let item: InputItem

    @State private var name: String = ""
    @State private var enabled = true
    @State private var kind: String = "none"
    @State private var host = ""
    @State private var port = "\(PlexampDriver.defaultPort)"

    var body: some View {
        Form {
            Section("Input \(item.number) · \(item.defaultName)") {
                TextField("Name", text: $name, prompt: Text(item.defaultName))
                Toggle("Enabled", isOn: $enabled)
            }
            Section {
                Picker("Playback target", selection: $kind) {
                    Text("None").tag("none")
                    ForEach(PlaybackTarget.Kind.availableHere) { k in Text(k.displayName).tag(k.rawValue) }
                }
                if kind == PlaybackTarget.Kind.plexamp.rawValue {
                    TextField("Plexamp host (e.g. 192.168.0.187)", text: $host)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("The Hegel IP protocol has no transport commands, so Prev / Play / Next go to the device that feeds this input. Plexamp: its Plex Companion player API on port 32500.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.name)
        .onAppear(perform: load)
        .onChange(of: name) { save() }
        .onChange(of: enabled) { save() }
        .onChange(of: kind) { save() }
        .onChange(of: host) { save() }
        .onChange(of: port) { save() }
    }

    private func load() {
        name = item.isRenamed ? item.name : ""
        enabled = item.isEnabled
        switch item.playbackTarget {
        case .plexamp(let h, let p):
            kind = PlaybackTarget.Kind.plexamp.rawValue
            host = h
            port = String(p)
        case .macMediaKeys:
            kind = PlaybackTarget.Kind.macMediaKeys.rawValue
        case nil:
            kind = "none"
        }
    }

    private var target: PlaybackTarget? {
        switch PlaybackTarget.Kind(rawValue: kind) {
        case .plexamp:
            let h = host.trimmingCharacters(in: .whitespaces)
            guard !h.isEmpty else { return nil }
            return .plexamp(host: h, port: Int(port) ?? PlexampDriver.defaultPort)
        case .macMediaKeys:
            return .macMediaKeys
        case nil:
            return nil
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        settings.update(InputSetting(number: item.number, name: trimmed.isEmpty ? nil : trimmed,
                                     isEnabled: enabled, playbackTarget: target))
    }
}
