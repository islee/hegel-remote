// MacMediaKeysDriver.swift: Mac-only playback driver that presses the system media keys.
//
// Purpose: drive whatever app owns Now Playing on this Mac (Music, Plexamp desktop, a browser) for an input
//   fed by the Mac.
// Context: posts NX_SYSDEFINED key events through the HID event tap, the same mechanism a keyboard's media keys
//   use. macOS may require Accessibility access for the app before posted events reach other apps; the driver
//   cannot detect that reliably, so a key that "does nothing" is the hint (README > Troubleshooting). No state:
//   media keys carry no feedback, so the row shows the buttons but no playing/paused indicator.
// Dependencies: AppKit (NSEvent), CoreGraphics (CGEvent).
#if os(macOS)
import AppKit
import Foundation

public struct MacMediaKeysDriver: PlaybackDriver {
    public let unavailableReason: String? = nil
    public let reportsState = false

    public init() {}

    // IOKit/hidsystem/ev_keymap.h values; the header is not importable from Swift without a bridging header.
    static let keyPlay: Int = 16
    static let keyNext: Int = 17
    static let keyPrevious: Int = 18

    public func send(_ command: PlaybackCommand) async throws {
        let key: Int
        switch command {
        case .playPause: key = Self.keyPlay
        case .next: key = Self.keyNext
        case .previous: key = Self.keyPrevious
        }
        await MainActor.run {
            post(key: key, down: true)
            post(key: key, down: false)
        }
    }

    public func poll() async throws -> PlaybackState? { nil }

    @MainActor
    private func post(key: Int, down: Bool) {
        // data1: key in the high 16 bits, key state (0xA down / 0xB up) in bits 8-15, as a real media key sends.
        let state = down ? 0xA : 0xB
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (state << 8), data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
#endif
