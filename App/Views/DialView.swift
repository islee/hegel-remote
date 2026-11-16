// DialView.swift: the central click wheel with the dot-matrix readout inside, and the slider alternative.
//
// Purpose: circular drag on the ring = volume detents (WheelDetentTracker); the inner disc shows volume and
//   source like the H590's display. `VolumeSliderView` is the same readout over a slider for the slider setting.
// Context: the drag never starts on the inner readout, so a tap there cannot change the volume. The displayed
//   number is the controller's `displayVolume` (pending target first), so the readout follows the finger.
// Dependencies: SwiftUI, Core.
import HegelRemoteCore
import SwiftUI

struct DialView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    @State private var tracker = WheelDetentTracker(detentsPerRevolution: 24)

    private let ringSize: CGFloat = 256
    private let readoutSize: CGFloat = 168

    var body: some View {
        let skin = settings.skin
        ZStack {
            Circle()
                .fill(skin.ringGradient)
                .overlay(Circle().stroke(skin.line, lineWidth: 1))
                .shadow(color: skin.shadow.opacity(0.55), radius: 18, x: 0, y: 12)
                .frame(width: ringSize, height: ringSize)
                .contentShape(Circle())
                .gesture(wheelGesture)
                .accessibilityLabel("Volume wheel")
                .accessibilityValue(controller.displayVolume.map { "\($0)" } ?? "unknown")
                .accessibilityAdjustableAction { direction in
                    controller.nudgeVolume(by: direction == .increment ? 1 : -1)
                }
            ReadoutDisc(size: readoutSize)
        }
        .frame(width: ringSize, height: ringSize)
        .disabled(!controller.isConnected)
        .opacity(controller.isConnected ? 1 : 0.6)
    }

    private var wheelGesture: some Gesture {
        let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // Ignore drags that start on the readout disc; those are not a turn of the wheel.
                let startRadius = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                guard startRadius >= readoutSize / 2 else { return }
                let angle = WheelDetentTracker.angle(of: value.location, around: center)
                if value.translation == .zero {
                    tracker.begin(angle: angle)
                } else {
                    let steps = tracker.update(angle: angle)
                    if steps != 0 { controller.nudgeVolume(by: steps) }
                }
            }
            .onEnded { _ in tracker.end() }
    }
}

/// The black disc: volume large on top, source name beneath, both in the readout font.
struct ReadoutDisc: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    var size: CGFloat = 180

    var body: some View {
        let skin = settings.skin
        let text = ReadoutText(controller: controller, settings: settings)
        VStack(spacing: 6) {
            Text(text.volume)
                .font(skin.readoutFont(size: size * 0.43))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(text.source)
                .font(skin.readoutFont(size: size * 0.085))
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
        }
        .foregroundStyle(skin.readoutForeground)
        .frame(width: size, height: size)
        .background(Circle().fill(skin.readoutBackground))
        .accessibilityElement(children: .combine)
    }
}

/// Slider alternative: readout disc above a slider with Vol -/+ at its ends.
struct VolumeSliderView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AmpController.self) private var controller
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let skin = settings.skin
        let range = controller.capabilities.volumeRange
        VStack(spacing: 18) {
            ReadoutDisc(size: 180)
            HStack(spacing: 12) {
                RoundIconButton(systemImage: "minus", skin: skin, size: 40, enabled: controller.isConnected) {
                    controller.nudgeVolume(by: -1)
                }
                Slider(
                    value: Binding(
                        get: { dragging ? dragValue : Double(controller.displayVolume ?? range.lowerBound) },
                        set: { dragValue = $0; controller.setVolume(Int($0.rounded())) }),
                    in: Double(range.lowerBound)...Double(range.upperBound), step: 1
                ) { Text("Volume") } onEditingChanged: { editing in
                    dragging = editing
                }
                .tint(skin.accent)
                .disabled(!controller.isConnected)
                RoundIconButton(systemImage: "plus", skin: skin, size: 40, enabled: controller.isConnected) {
                    controller.nudgeVolume(by: 1)
                }
            }
        }
    }
}
