// FontRegistry.swift: registers the bundled readout font at launch and reports whether it is available.
//
// Purpose: one code path for both platforms (no `UIAppFonts` / `ATSApplicationFontsPath` plist keys to keep in
//   sync). Doto is a variable TTF (SIL OFL 1.1, licence beside it in Resources); SwiftUI selects the weight on
//   the family name.
// Context: registration is per process and idempotent for our purpose: a second call reports "already
//   registered", which is ignored.
// Dependencies: CoreText, Foundation.
import CoreText
import Foundation

public enum FontRegistry {
    public static let dotoFamily = "Doto"
    static let bundledFonts = ["Doto-Variable"]

    /// Registers every bundled font. Safe to call more than once.
    public static func registerBundledFonts(bundle: Bundle = .main) {
        for name in bundledFonts {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// True when a font of the Doto family can be created (so views can fall back to system monospaced).
    public static var isDotoAvailable: Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: dotoFamily] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        return (CTFontCopyFamilyName(font) as String) == dotoFamily
    }
}
