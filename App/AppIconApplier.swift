// AppIconApplier.swift: makes the app icon match `SettingsStore.iconChoice` at runtime.
//
// Purpose: iOS swaps the home-screen icon with `setAlternateIconName`; the Mac sets the Dock icon image.
// Context: the pure choice logic (names, availability, follow-the-model rule) is `IconChoice`/`AppIcons` in Core.
//   iOS: the call shows a system alert, so it runs only when the wanted name differs from the current one, and a
//   failure is kept in `lastError` for Settings to show (the stored choice is kept; the next change retries).
//   macOS: `NSApp.applicationIconImage` only lasts while the app runs. The Finder and the Dock show the default
//   icon (the bundle's AppIcon) when the app is not running; a Mac app cannot change that. The Dock image
//   comes from the `DockIcon-*-Light/Dark` image sets and is re-applied when the effective appearance changes
//   (KVO on `NSApp.effectiveAppearance`) and when the choice or the appearance setting changes.
// Dependencies: SwiftUI, UIKit / AppKit, Core.
import HegelRemoteCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class AppIconApplier {
    private let settings: SettingsStore
    /// Last failure from the system, for Settings; nil after a successful apply.
    var lastError: String?
    #if os(macOS)
    private var appearanceObservation: NSKeyValueObservation?
    #endif

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Bring the icon in line with the settings. Safe to call often.
    func apply() {
        #if os(iOS)
        let wanted = settings.effectiveIconChoice.alternateIconName
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != wanted else { return }
        Task {
            do {
                try await app.setAlternateIconName(wanted)
                lastError = nil
            } catch {
                lastError = "Couldn't change the app icon: \(error.localizedDescription)"
            }
        }
        #else
        startObservingIfNeeded()
        let name = settings.effectiveIconChoice.dockImageName(dark: dockIsDark)
        guard let image = NSImage(named: name) else {
            lastError = "Missing Dock image \(name)."
            return
        }
        NSApp.applicationIconImage = image
        lastError = nil
        #endif
    }

    #if os(macOS)
    /// Dark when the setting says so, or (System) when the app's effective appearance is dark.
    private var dockIsDark: Bool {
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return settings.appearance.isDark(systemIsDark: systemDark)
    }

    private func startObservingIfNeeded() {
        guard appearanceObservation == nil, let app = NSApp else { return }
        appearanceObservation = app.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.apply() }
        }
    }
    #endif
}
