import Foundation
import CoreGraphics

/// Easing curves, t in 0…1.
public enum Ease {
    public static func clamp(_ t: Double) -> Double { max(0, min(1, t)) }
    public static func outCubic(_ t: Double) -> Double { let u = 1 - clamp(t); return 1 - u * u * u }
    public static func outQuint(_ t: Double) -> Double { let u = 1 - clamp(t); return 1 - u * u * u * u * u }
    public static func inOutCubic(_ t: Double) -> Double {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    public static func outBack(_ t: Double, _ s: Double = 1.6) -> Double {
        let u = clamp(t) - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }
    public static func clamp01(_ t: Double) -> Double { clamp(t) }
    public static func inCubic(_ t: Double) -> Double { let u = clamp(t); return u * u * u }
    public static func inOutSine(_ t: Double) -> Double { -(cos(.pi * clamp(t)) - 1) / 2 }
    public static func outElastic(_ t: Double) -> Double {
        let u = clamp(t)
        if u == 0 || u == 1 { return u }
        return pow(2, -10 * u) * sin((u * 10 - 0.75) * (2 * .pi / 3)) + 1
    }
    /// 0 → 1 → 0 bump, handy for flashes.
    public static func bump(_ t: Double) -> Double { let t = clamp(t); return sin(t * .pi) }
}

/// Critically-damped follower: `value` chases `target` and reports when it has settled (so modes can stop animating).
public struct Smoothed {
    public var value: Double
    public var target: Double
    /// Larger = snappier. ~18 feels like a UIKit spring.
    public var speed: Double
    private var velocity: Double = 0

    public init(_ v: Double = 0, speed: Double = 18) { value = v; target = v; self.speed = speed }

    public mutating func step(_ dt: Double) {
        let omega = speed
        let x = omega * dt
        let exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * exp
        value = target + (change + temp) * exp
        if settled { value = target; velocity = 0 }
    }

    public mutating func snap(_ v: Double) { value = v; target = v; velocity = 0 }
    public var settled: Bool { abs(value - target) < 0.0015 && abs(velocity) < 0.01 }
    public var cg: CGFloat { CGFloat(value) }
}

/// Per-element press feedback: rises instantly on touch-down, eases out after release
/// (with a guaranteed visible flash even for very quick taps).
public final class Presses<Key: Hashable> {
    private var values: [Key: Double] = [:]
    private var held: Set<Key> = []
    public init() {}

    public func press(_ k: Key) { held.insert(k); values[k] = max(values[k] ?? 0, 0.35) }
    public func release(_ k: Key) { held.remove(k); values[k] = max(values[k] ?? 0, 0.85) }
    public func releaseAll() { for k in held { values[k] = max(values[k] ?? 0, 0.85) }; held.removeAll() }
    public func cancelAll() { held.removeAll() }
    public func amount(_ k: Key) -> CGFloat { CGFloat(values[k] ?? 0) }
    public func isHeld(_ k: Key) -> Bool { held.contains(k) }

    public func step(_ dt: Double) {
        for (k, v) in values {
            if held.contains(k) { values[k] = min(1, v + dt * 14) }
            else {
                let n = v - dt * 3.2
                values[k] = n <= 0 ? nil : n
            }
        }
    }

    /// True while something is still moving (fully-held keys are static).
    public var animating: Bool { values.contains { !held.contains($0.key) || $0.value < 1 } }
}

/// Horizontal scroller with momentum and rubber-banding, shared by every scrolling row.
public struct Scroller {
    public var offset: CGFloat = 0
    public var maxOffset: CGFloat = 0
    public private(set) var dragging = false
    private var startOffset: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastX: CGFloat = 0
    private var lastT: Double = 0

    public init() {}

    public mutating func begin(_ t: StripTouch) { dragging = false; velocity = 0; startOffset = offset; lastX = t.x; lastT = t.time }

    /// Returns true once the touch has turned into a scroll.
    @discardableResult
    public mutating func move(_ t: StripTouch, slop: CGFloat = 8) -> Bool {
        if !dragging, abs(t.dx) > slop, maxOffset > 0 { dragging = true; startOffset = offset + (t.dx > 0 ? slop : -slop) }
        guard dragging else { return false }
        let raw = startOffset - t.dx
        offset = raw < 0 ? raw * 0.35 : (raw > maxOffset ? maxOffset + (raw - maxOffset) * 0.35 : raw)
        let dt = t.time - lastT
        if dt > 0.004 { velocity = velocity * 0.3 + 0.7 * (lastX - t.x) / CGFloat(dt) }
        lastX = t.x; lastT = t.time
        return true
    }

    public mutating func end(_ t: StripTouch) {
        if !dragging || t.time - lastT > 0.08 { velocity = 0 }
        dragging = false
    }

    public mutating func step(_ dt: Double) {
        guard !dragging else { return }
        let d = CGFloat(dt)
        if abs(velocity) > 4 {
            offset += velocity * d
            velocity *= CGFloat(pow(0.035, dt))
            if offset < 0 || offset > maxOffset { velocity *= CGFloat(pow(0.0005, dt)) }
        } else { velocity = 0 }
        if offset < 0 { offset += (0 - offset) * min(1, d * 14); if offset > -0.3 { offset = 0 } }
        if offset > maxOffset { offset += (maxOffset - offset) * min(1, d * 14); if offset - maxOffset < 0.3 { offset = maxOffset } }
    }

    public var animating: Bool { dragging || velocity != 0 || offset < 0 || offset > maxOffset }
}
