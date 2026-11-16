// RootView.swift: setup screen until an amp is remembered, then the main screen.
//
// Purpose: the one switch between "no amp yet" and "remote". Also hosts the error toast so every screen
//   shares it.
// Dependencies: SwiftUI, SettingsStore, AmpController.
import HegelRemoteCore
import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller

    var body: some View {
        ZStack(alignment: .bottom) {
            if settings.ampAddress == nil {
                SetupView()
            } else {
                MainView()
            }
            if let message = controller.lastError {
                ErrorToast(message: message) { controller.lastError = nil }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.lastError)
        .preferredColorScheme(settings.skin.colorScheme)
    }
}

struct ErrorToast: View {
    let message: String
    let dismiss: () -> Void
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let skin = settings.skin
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote).lineLimit(3)
            Spacer(minLength: 0)
            Button("OK", action: dismiss).font(.footnote.weight(.bold))
        }
        .foregroundStyle(skin.foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(skin.button))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(skin.line))
        .padding(.horizontal, 22)
        .task(id: message) {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}
