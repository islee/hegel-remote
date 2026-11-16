// CustomButtonEditor.swift: list, add, edit and delete custom buttons and their ordered actions.
//
// Purpose: the editor for `CustomButton` data: label plus actions (amp commands, HTTP requests).
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct CustomButtonsEditor: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach($settings.customButtons) { $button in
                    NavigationLink {
                        CustomButtonDetailEditor(button: $button)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(button.label.isEmpty ? "Untitled" : button.label)
                            Text(button.actions.map { $0.label(inputName: settings.inputName) }.joined(separator: " → "))
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .onDelete { settings.customButtons.remove(atOffsets: $0) }
                .onMove { settings.customButtons.move(fromOffsets: $0, toOffset: $1) }
                Button("Add button") {
                    settings.customButtons.append(CustomButton(label: "New button", actions: []))
                }
            } footer: {
                Text("Actions run in order; an amp command waits for the amplifier's reply before the next one. The HTTP action can call a Home Assistant webhook. DAC-Loop cannot be switched over IP (menu-only on the amp), so it is not offered.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Custom buttons")
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
}

struct CustomButtonDetailEditor: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var button: CustomButton
    @State private var volumeToAdd = 30
    @State private var inputToAdd = 12
    @State private var httpURL = ""
    @State private var httpMethod = "POST"
    @State private var httpBody = ""

    var body: some View {
        Form {
            Section("Button") {
                TextField("Label", text: $button.label)
            }
            Section("Actions, in order") {
                if button.actions.isEmpty {
                    Text("No actions yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(button.actions.enumerated()), id: \.offset) { index, action in
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(action.label(inputName: settings.inputName)).lineLimit(2)
                    }
                }
                .onDelete { button.actions.remove(atOffsets: $0) }
                .onMove { button.actions.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Add an amp command") {
                HStack {
                    Button("Power on") { add(.amp(.power(true))) }
                    Spacer()
                    Button("Power off") { add(.amp(.power(false))) }
                    Spacer()
                    Button("Mute") { add(.amp(.mute(true))) }
                    Spacer()
                    Button("Unmute") { add(.amp(.mute(false))) }
                }
                .buttonStyle(.bordered)
                HStack {
                    Stepper("Volume \(volumeToAdd)", value: $volumeToAdd, in: settings.capabilities.volumeRange)
                    Button("Add") { add(.amp(.setVolume(volumeToAdd))) }.buttonStyle(.bordered)
                }
                HStack {
                    Picker("Input", selection: $inputToAdd) {
                        ForEach(settings.inputs) { Text($0.name).tag($0.number) }
                    }
                    Button("Add") { add(.amp(.selectInput(inputToAdd))) }.buttonStyle(.bordered)
                }
            }
            Section {
                Picker("Method", selection: $httpMethod) {
                    ForEach(["GET", "POST", "PUT"], id: \.self) { Text($0) }
                }
                TextField("URL (http://homeassistant.local:8123/api/webhook/…)", text: $httpURL)
                    .autocorrectionDisabled()
                TextField("Body (optional JSON)", text: $httpBody, axis: .vertical)
                    .lineLimit(1...4)
                Button("Add HTTP request") {
                    add(.http(HTTPRequestSpec(method: httpMethod, url: httpURL.trimmingCharacters(in: .whitespaces),
                                              body: httpBody.isEmpty ? nil : httpBody)))
                    httpURL = ""
                    httpBody = ""
                }
                .disabled(URL(string: httpURL.trimmingCharacters(in: .whitespaces))?.host() == nil)
            } header: {
                Text("Add an HTTP request")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(button.label)
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }

    private func add(_ action: ButtonAction) {
        button.actions.append(action)
    }
}
