// MenuBarView.swift: the Mac menu bar popover: readout, volume slider, mute/power, inputs, quit.
//
// Purpose: the compact remote from Docs/design/canvas/Mac.dc.html. Same controller as the window.
// Dependencies: SwiftUI, Core. macOS only.
#if os(macOS)
import HegelRemoteCore
import SwiftUI

struct MenuBarView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    @Environment(\.openSettings) private var openSettings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        let skin = settings.skin
        let text = ReadoutText(controller: controller, settings: settings)
        let range = controller.capabilities.volumeRange
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.ampAddress?.title ?? "No amplifier").font(.system(size: 14, weight: .bold))
                Spacer()
                ConnectionBadge(phase: controller.phase, skin: skin)
                RoundIconButton(systemImage: controller.amp.mute == true ? "speaker.slash.fill" : "speaker.wave.2",
                                skin: skin, size: 30, enabled: controller.isConnected) { controller.toggleMute() }
                RoundIconButton(systemImage: "power", skin: skin, size: 30,
                                tint: controller.amp.power == false ? skin.muted : skin.accent,
                                enabled: controller.isConnected) { controller.togglePower() }
            }
            HStack(alignment: .lastTextBaseline) {
                Text(text.source).font(skin.readoutFont(size: 18)).tracking(1)
                Spacer()
                Text(text.volume).font(skin.readoutFont(size: 40))
            }
            .foregroundStyle(skin.readoutForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(skin.readoutBackground))
            Slider(
                value: Binding(
                    get: { Double(controller.displayVolume ?? range.lowerBound) },
                    set: { controller.setVolume(Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .disabled(!controller.isConnected)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(controller.inputs) { input in
                    Button(input.name) { controller.selectInput(input.number) }
                        .buttonStyle(SkinButtonStyle(skin: skin, selected: controller.amp.input == input.number, cornerRadius: 8))
                        .disabled(!controller.isConnected)
                }
            }
            HStack {
                Button("Settings…") { openSettings() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundStyle(skin.muted)
        }
        .padding(16)
        .frame(width: 300)
        .background(skin.background)
        .foregroundStyle(skin.foreground)
        .tint(skin.accent)
        .followsTheme()
    }
}
#endif
