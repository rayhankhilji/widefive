import Foundation

/// Global multi-touch gestures layered above modes.
///  • 2-finger horizontal slide → volume       • 3-finger slide → brightness
///  • 2-finger tap → play/pause                • swipe in from the left edge → launcher
///  • fast 1-finger flick (≥ 280pt in < 0.25s) → next / previous mode in `flickOrder`
public final class GestureEngine {
    public enum Output { case volume(Float), brightness(Float), playPause, launcher, flick(Int) }

    public var config = GestureConfig()
    public var emit: (Output) -> Void = { _ in }

    private var touches: [Int: StripTouch] = [:]
    private var maxFingers = 0
    private var claimed = false
    private var startValue: Float = 0
    private var startCentroid: CGFloat = 0
    private var groupStart: Double = 0
    private var moved = false

    public init() {}

    /// Returns true when the gesture engine has taken over the current touch group (mode should get cancels).
    public var isClaiming: Bool { claimed }

    /// Forget a touch without acting on it (it ended while a mode without gestures was showing).
    public func forget(_ id: Int) {
        touches[id] = nil
        if touches.isEmpty { claimed = false; maxFingers = 0 }
    }

    /// Drop all tracked touches (mode switches, wake). A touch whose end we never heard about must never linger:
    /// it would make every later single tap look like a two-finger gesture.
    public func reset() {
        touches.removeAll(); claimed = false; maxFingers = 0; moved = false
    }

    public func began(_ t: StripTouch) -> Bool {
        // Self-heal: a finger that hasn't reported anything for a while is a lost touch, not one still on the glass.
        touches = touches.filter { t.time - $0.value.time < 4 }
        if touches.isEmpty { maxFingers = 0; claimed = false; moved = false; groupStart = t.time }
        touches[t.id] = t
        maxFingers = max(maxFingers, touches.count)
        guard config.enabled else { return false }
        if touches.count >= 2, (config.twoFingerVolume || config.threeFingerBrightness || config.twoFingerTapPlayPause) {
            if !claimed { claimed = true }
            startCentroid = centroid
            startValue = touches.count >= 3 ? SystemControl.brightness : SystemControl.volume
            return true
        }
        return claimed
    }

    public func moved(_ t: StripTouch) -> Bool {
        touches[t.id] = t
        guard config.enabled else { return false }
        if claimed {
            let delta = centroid - startCentroid
            if abs(delta) > 6 { moved = true }
            let v = startValue + Float(delta / 400)
            if maxFingers >= 3, config.threeFingerBrightness { emit(.brightness(max(0, min(1, v)))) }
            else if maxFingers == 2, config.twoFingerVolume { emit(.volume(max(0, min(1, v)))) }
            return true
        }
        return false
    }

    public func ended(_ t: StripTouch) -> Bool {
        let wasClaimed = claimed
        touches[t.id] = nil
        guard config.enabled else { return false }
        if wasClaimed {
            if touches.isEmpty {
                if !moved, maxFingers == 2, t.time - groupStart < 0.35, config.twoFingerTapPlayPause { emit(.playPause) }
                claimed = false
            }
            return true
        }
        if touches.isEmpty, maxFingers == 1 {
            if config.edgeSwipeLauncher, t.startX < 14, t.dx > 90 { emit(.launcher); return true }
            if config.flickModes, abs(t.dx) > 280, t.duration < 0.25 { emit(.flick(t.dx < 0 ? 1 : -1)); return true }
        }
        return false
    }

    private var centroid: CGFloat {
        guard !touches.isEmpty else { return 0 }
        return touches.values.map(\.x).reduce(0, +) / CGFloat(touches.count)
    }
}
