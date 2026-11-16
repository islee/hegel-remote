// ThemeSync.swift: the SwiftUI side of "skin follows the system theme".
//
// Purpose: apply the appearance setting as the scene's preferred colour scheme (nil = follow the system) and feed
//   the observed system scheme back into `SettingsStore.systemIsDark`, which `SettingsStore.skin` resolves from.
// Context: used on every root of a scene (window, menu bar popover, Mac Settings scene). With an explicit
//   Light/Dark setting the resolver ignores `systemIsDark`, so the scheme that SwiftUI reports while forcing one
//   does not matter; with System nothing is forced, so the value is the real system scheme.
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

extension AppearanceSetting {
    /// nil lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct FollowsTheme: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settings.appearance.colorScheme)
            .onChange(of: colorScheme, initial: true) { _, scheme in settings.systemIsDark = scheme == .dark }
    }
}

extension View {
    /// Apply the appearance setting and keep `SettingsStore.systemIsDark` current. Needs `SettingsStore` in the environment.
    func followsTheme() -> some View { modifier(FollowsTheme()) }
}
