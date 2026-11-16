// MainView.swift: the remote, laid out as in Docs/design/canvas/Dial.dc.html.
//
// Purpose: header (title, status, mute, power), the dial or slider, playback row, inputs, custom buttons.
//   Sections appear according to the model's capability table; the view never branches on a model id.
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct MainView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    // `-showSettings YES` opens the sheet at launch (Docs/screenshots/make.sh).
    @State private var showSettings = UserDefaults.standard.bool(forKey: "showSettings")

    var body: some View {
        let skin = settings.skin
        let caps = controller.capabilities
        ScrollView {
            VStack(spacing: 14) {
                header(skin: skin, caps: caps)

                if caps.supports(.volume) {
                    if settings.volumeControl == .wheel {
                        DialView()
                            .padding(.vertical, 2)
                    } else {
                        VolumeSliderView()
                            .padding(.vertical, 8)
                    }
                }

                PlaybackRow()

                if caps.supports(.input) {
                    InputsSection(openSettings: { showSettings = true })
                }

                CustomButtonsSection(openSettings: { showSettings = true })
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(skin.background.ignoresSafeArea())
        .foregroundStyle(skin.foreground)
        .tint(skin.accent)
        .sheet(isPresented: $showSettings, onDismiss: { controller.settingsDidChange() }) {
            SettingsView()
                .environment(settings)
                .environment(controller)
        }
    }

    private func header(skin: Skin, caps: ModelCapabilities) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Button { showSettings = true } label: {
                    HStack(spacing: 6) {
                        Text(skin.name.uppercased())
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1.6)
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(skin.muted)
                }
                .buttonStyle(.plain)
                Text(settings.ampAddress?.title ?? "")
                    .font(.system(size: 20, weight: .bold))
                ConnectionBadge(phase: controller.phase, skin: skin)
            }
            Spacer()
            if caps.supports(.mute) {
                RoundIconButton(
                    systemImage: controller.amp.mute == true ? "speaker.slash.fill" : "speaker.wave.2",
                    skin: skin, tint: controller.amp.mute == true ? skin.accent : skin.foreground,
                    enabled: controller.isConnected) { controller.toggleMute() }
                    .accessibilityLabel("Mute")
            }
            if caps.supports(.power) {
                RoundIconButton(
                    systemImage: "power", skin: skin,
                    tint: controller.amp.power == false ? skin.muted : skin.accent,
                    enabled: controller.isConnected) { controller.togglePower() }
                    .accessibilityLabel("Power")
            }
        }
    }
}

struct ConnectionBadge: View {
    let phase: AmpController.Phase
    let skin: Skin

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(phase.label).font(.system(size: 12, weight: .medium)).foregroundStyle(skin.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch phase {
        case .connected: .green
        case .connecting: .yellow
        case .unreachable: .red
        case .idle: skin.muted
        }
    }
}
