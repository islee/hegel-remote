// WheelDetentTracker.swift: turns a circular drag into discrete detents, iPod click-wheel style.
//
// Purpose: the dial view feeds it the finger's angle around the ring; it returns how many detents were crossed
//   since the last update (clockwise positive). One detent = one volume step, so the view never does geometry.
// Context: pure value type. Angles are in radians from `atan2(dy, dx)` in view coordinates (y grows downward),
//   where a clockwise turn increases the angle. Wrap-around at +-pi is handled by normalising each delta.
// Dependencies: Foundation (atan2, fmod).
import Foundation

public struct WheelDetentTracker: Sendable, Equatable {
    public var detentsPerRevolution: Int
    private var lastAngle: Double?
    private var accumulated: Double = 0

    public init(detentsPerRevolution: Int = 24) {
        self.detentsPerRevolution = max(1, detentsPerRevolution)
    }

    public var detentAngle: Double { 2 * .pi / Double(detentsPerRevolution) }

    /// Angle of `point` around `center`, in radians, clockwise-positive in view coordinates.
    public static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        atan2(point.y - center.y, point.x - center.x)
    }

    /// Call on touch-down. Returns no steps: a tap must never change the volume.
    public mutating func begin(angle: Double) {
        lastAngle = angle
        accumulated = 0
    }

    /// Call on every drag update. Returns detents crossed since the previous call (0 most of the time).
    public mutating func update(angle: Double) -> Int {
        guard let last = lastAngle else {
            begin(angle: angle)
            return 0
        }
        var delta = angle - last
        // Normalise into (-pi, pi] so crossing the +-pi seam counts as a small move, not a full turn back.
        while delta > .pi { delta -= 2 * .pi }
        while delta <= -.pi { delta += 2 * .pi }
        lastAngle = angle
        accumulated += delta
        let steps = Int((accumulated / detentAngle).rounded(.towardZero))
        accumulated -= Double(steps) * detentAngle
        return steps
    }

    public mutating func end() {
        lastAngle = nil
        accumulated = 0
    }
}
