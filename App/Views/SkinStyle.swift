// SkinStyle.swift: SwiftUI glue for skins: colours, readout font, shared button styles.
//
// Purpose: the only place `Skin` data becomes SwiftUI types, so views stay declarative and a new skin field
//   is handled once here.
// Context: the readout font is a variable TTF registered by FontRegistry; SwiftUI applies the weight on the
//   family name. When Doto is unavailable the monospaced system font takes over.
// Dependencies: SwiftUI, Core (Skin, FontRegistry).
import HegelRemoteCore
import SwiftUI

extension Color {
    init(_ hex: HexColor) {
        self.init(.sRGB, red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha)
    }
}

extension Skin {
    var background: Color { Color(colors.background) }
    var foreground: Color { Color(colors.foreground) }
    var muted: Color { Color(colors.muted) }
    var line: Color { Color(colors.line) }
    var button: Color { Color(colors.button) }
    var accent: Color { Color(colors.accent) }
    var readoutBackground: Color { Color(colors.readoutBackground) }
    var readoutForeground: Color { Color(colors.readoutForeground) }
    var shadow: Color { Color(colors.shadow) }

    /// The dial ring: a highlight at the upper left, as on a machined knob.
    var ringGradient: RadialGradient {
        RadialGradient(
            colors: [Color(colors.ringHighlight), Color(colors.ringMid), Color(colors.ringShadow)],
            center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: 150)
    }

    /// Dot-matrix readout font at `size`.
    func readoutFont(size: CGFloat) -> Font {
        switch readoutFont {
        case .doto where FontRegistry.isDotoAvailable:
            return .custom(FontRegistry.dotoFamily, size: size).weight(.black)
        default:
            return .system(size: size, weight: .black, design: .monospaced)
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// Section caption: small caps with wide tracking ("INPUTS").
struct SectionCaption: View {
    let text: String
    let skin: Skin
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(skin.muted)
    }
}

/// A round icon button (mute, power, transport).
struct RoundIconButton: View {
    let systemImage: String
    let skin: Skin
    var size: CGFloat = 48
    var tint: Color? = nil
    var filled = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(filled ? skin.background : (tint ?? skin.foreground))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? skin.foreground : skin.button))
                .overlay(Circle().stroke(filled ? skin.foreground : skin.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// A pill or rounded-rectangle text button used by inputs and custom buttons.
struct SkinButtonStyle: ButtonStyle {
    let skin: Skin
    var selected = false
    var dashed = false
    var cornerRadius: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(.system(size: 14, weight: selected ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? skin.background : (dashed ? skin.muted : skin.foreground))
            .background(shape.fill(selected ? skin.foreground : (dashed ? Color.clear : skin.button)))
            .overlay(shape.strokeBorder(selected ? skin.foreground : skin.line,
                                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(shape)
    }
}
