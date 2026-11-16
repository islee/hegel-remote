// InputsSection.swift: the enabled inputs as a 3-column grid, current one filled, plus an Edit tile.
//
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct InputsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    let openSettings: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        let skin = settings.skin
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Inputs", skin: skin)
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(controller.inputs) { input in
                    Button(input.name) { controller.selectInput(input.number) }
                        .buttonStyle(SkinButtonStyle(skin: skin, selected: controller.amp.input == input.number))
                        .disabled(!controller.isConnected)
                        .accessibilityLabel("Input \(input.name)")
                        .accessibilityAddTraits(controller.amp.input == input.number ? .isSelected : [])
                }
                Button("Edit", action: openSettings)
                    .buttonStyle(SkinButtonStyle(skin: skin, dashed: true))
            }
        }
    }
}
