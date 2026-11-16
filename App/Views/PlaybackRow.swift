// PlaybackRow.swift: Prev / Play-Pause / Next for the current input's playback target, with its caption.
//
// Purpose: show the transport row always (the design has it), enabled only when the current input has a
//   driver that can act; otherwise dimmed with the one-line reason from the driver.
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct PlaybackRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller

    var body: some View {
        let skin = settings.skin
        let reason = controller.playbackUnavailableReason
        let enabled = reason == nil && controller.isConnected
        let playing = controller.playbackState?.isPlaying == true
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                RoundIconButton(systemImage: "backward.end.fill", skin: skin, size: 52, enabled: enabled) {
                    controller.playback(.previous)
                }
                .accessibilityLabel("Previous track")
                RoundIconButton(systemImage: playing ? "pause.fill" : "play.fill", skin: skin, size: 52,
                                filled: true, enabled: enabled) {
                    controller.playback(.playPause)
                }
                .accessibilityLabel("Play or pause")
                RoundIconButton(systemImage: "forward.end.fill", skin: skin, size: 52, enabled: enabled) {
                    controller.playback(.next)
                }
                .accessibilityLabel("Next track")
            }
            Text(caption(reason: reason))
                .font(.system(size: 12))
                .foregroundStyle(skin.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func caption(reason: String?) -> String {
        if let reason { return reason }
        guard let input = controller.currentInput, let target = input.playbackTarget else { return "" }
        var text = "Playback via \(target.caption) (mapped to \(input.name))"
        if let title = controller.playbackState?.title, !title.isEmpty { text += " · \(title)" }
        return text
    }
}
