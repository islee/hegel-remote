// CustomButtonsSection.swift: the user's preset buttons in a wrapping row, plus "+ Add".
//
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct CustomButtonsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    let openSettings: () -> Void

    var body: some View {
        let skin = settings.skin
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Custom", skin: skin)
            WrappingHStack(spacing: 8) {
                ForEach(settings.customButtons) { button in
                    Button(button.label) { controller.run(button) }
                        .buttonStyle(SkinButtonStyle(skin: skin, cornerRadius: 12))
                        .fixedSize()
                }
                Button("+ Add", action: openSettings)
                    .buttonStyle(SkinButtonStyle(skin: skin, dashed: true, cornerRadius: 12))
                    .fixedSize()
            }
        }
    }
}

/// Minimal flow layout: lays children left to right and wraps. iOS 16+/macOS 13+ `Layout`.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
