// SetupView.swift: find the amp (Bonjour) or type its address, pick the model, remember it.
//
// Purpose: first-run screen and the "change amplifier" screen. Discovery fills the model from the Bonjour name
//   (`D8F710D3E204@H590`); a manual entry defaults to H590 and the picker lists the other models as untested.
// Context: discovery only yields amps that answered a read-only status query on port 50001.
// Dependencies: SwiftUI, HegelDiscovery, Core.
import HegelRemoteCore
import HegelDiscovery
import HegelProtocol
import SwiftUI

struct SetupView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var found: [DiscoveredAmp] = []
    @State private var searching = false
    @State private var manualText = ""
    @State private var manualModelID = AmpModel.h590.id
    @State private var manualName = ""
    @State private var manualError: String?

    var body: some View {
        let skin = settings.skin
        NavigationStack {
            Form {
                Section {
                    if found.isEmpty {
                        HStack {
                            if searching { ProgressView().controlSize(.small) }
                            Text(searching ? "Looking for Hegel amplifiers…" : "No amplifier found yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(found, id: \.host) { amp in
                        Button {
                            save(AmpAddress(host: amp.host, port: amp.port, modelID: amp.model?.id ?? AmpModel.h590.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(amp.model?.displayName ?? amp.name).font(.headline)
                                Text("\(amp.host) · \(amp.name)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(searching ? "Searching…" : "Search again") { Task { await discover() } }
                        .disabled(searching)
                } header: {
                    Text("On this network")
                } footer: {
                    Text("Discovery uses the amplifier's AirPlay announcement and confirms it on port 50001. Only read-only status queries are sent.")
                }

                Section {
                    TextField("192.168.0.10 or host:port", text: $manualText)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        #endif
                    Picker("Model", selection: $manualModelID) {
                        ForEach(ModelCapabilities.all, id: \.modelID) { cap in
                            Text(cap.pickerLabel).tag(cap.modelID)
                        }
                    }
                    TextField("Name (optional, e.g. Living room)", text: $manualName)
                    if let manualError {
                        Text(manualError).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Connect") { saveManual() }
                        .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Or enter the address")
                } footer: {
                    Text(ModelCapabilities.capabilities(for: manualModelID).notes)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Amplifier")
            .toolbar {
                if settings.ampAddress != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .tint(skin.accent)
        .task { await discover() }
    }

    private func discover() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        for await amp in AmpDiscovery.discover(timeout: 6) {
            if !found.contains(where: { $0.host == amp.host }) { found.append(amp) }
        }
    }

    private func saveManual() {
        guard var address = AmpAddress.parse(manualText) else {
            manualError = "Enter an IP address or host name, optionally with :port."
            return
        }
        address.modelID = manualModelID
        let name = manualName.trimmingCharacters(in: .whitespaces)
        address.name = name.isEmpty ? nil : name
        save(address)
    }

    private func save(_ address: AmpAddress) {
        settings.ampAddress = address
        controller.reconnect()
        dismiss()
    }
}
