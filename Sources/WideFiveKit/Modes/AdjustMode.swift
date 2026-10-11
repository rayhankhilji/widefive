import AppKit

/// Shared get/set for the Apple-style quick controls: screen brightness, keyboard backlight, volume.
public enum QuickControl {
    public static func value(_ name: String) -> Float {
        switch name {
        case "brightness": return SystemControl.brightness
        case "keyboard": return KeyboardLight.brightness
        default: return SystemControl.isMuted ? 0 : SystemControl.volume
        }
    }

    public static func set(_ name: String, _ v: Float) {
        let v = max(0, min(1, v))
        switch name {
        case "brightness": SystemControl.brightness = v
        case "keyboard": KeyboardLight.brightness = v
        default:
            if SystemControl.isMuted { SystemControl.setMuted(false) }
            SystemControl.volume = v
        }
    }

    public static func icon(_ name: String, v: Float) -> String {
        switch name {
        case "brightness": return v < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case "keyboard": return v < 0.35 ? "light.min" : "light.max"
        default: return v <= 0.001 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    public static func title(_ name: String) -> String {
        ["brightness": "Brightness", "keyboard": "Keyboard Light", "volume": "Volume"][name] ?? name.capitalized
    }
}

/// Full-width slider that takes over the bar when you tap a quick control, like Apple's Control Strip.
/// Drag anywhere on it; it slides back to where you were after a few idle seconds.
public final class AdjustMode: StripMode {
    public let id: String
    public let title: String
    public let icon: String
    public var isAnimated: Bool { true }
    public var allowsGestures: Bool { false }
    public var showsExitButton: Bool { true }

    let kind: String
    private var ctx: ModeContext?
    private var shown = Smoothed(0.5, speed: 26)
    private var grab = Smoothed(0, speed: 20)
    private var idle: Double = 0
    private var touching = false
    private var trackRect: CGRect = .zero

    public init(_ kind: String) {
        self.kind = kind
        id = "adjust.\(kind)"
        title = QuickControl.title(kind)
        icon = QuickControl.icon(kind, v: 1)
    }

    public func activate(_ ctx: ModeContext) {
        self.ctx = ctx
        idle = 0
        touching = false
        shown.snap(Double(QuickControl.value(kind)))
    }

    public func update(dt: Double) {
        if !touching { shown.target = Double(QuickControl.value(kind)) }
        shown.step(dt)
        grab.target = touching ? 1 : 0
        grab.step(dt)
        if touching { idle = 0 } else { idle += dt }
        if idle > 3.5 { idle = -.infinity; ctx?.goBack() }
    }

    public func draw(_ c: Canvas) {
        let x0 = Metrics.contentX
        let v = CGFloat(max(0, min(1, shown.value)))
        let r = CGRect(x: x0, y: 1.5, width: c.width - x0 - 2, height: c.height - 3)
        c.panel(r)
        let right: CGFloat = 78
        c.symbol(QuickControl.icon(kind, v: 0.1), in: CGRect(x: r.minX + 4, y: r.minY, width: 26, height: r.height), color: c.theme.dim, pointSize: Metrics.iconSmall)
        c.symbol(QuickControl.icon(kind, v: 1), in: CGRect(x: r.maxX - right, y: r.minY, width: 26, height: r.height), color: c.theme.text, pointSize: Metrics.icon)
        c.text("\(Int((v * 100).rounded()))%", x: r.maxX - 10, size: 12, color: c.theme.text, weight: .semibold, mono: true, align: .right)
        let track = CGRect(x: r.minX + 36, y: r.midY - 3, width: r.maxX - right - 8 - (r.minX + 36), height: 6)
        trackRect = track
        c.meter(track, value: v)
        let g = grab.cg
        let knob = CGPoint(x: track.minX + track.width * v, y: track.midY)
        c.glowing(c.theme.accent, blur: 8, strength: 0.5 + 0.5 * g) {
            c.circle(center: knob, radius: 8 + 2 * g, c.theme.isLight ? .white : c.theme.text)
        }
    }

    private func setFrom(_ x: CGFloat) {
        guard trackRect.width > 0 else { return }
        let v = Float(max(0, min(1, (x - trackRect.minX) / trackRect.width)))
        shown.target = Double(v)
        QuickControl.set(kind, v)
        ctx?.requestRedraw()
    }

    public func touchBegan(_ t: StripTouch) { touching = true; setFrom(t.x) }
    public func touchMoved(_ t: StripTouch) { setFrom(t.x) }
    public func touchEnded(_ t: StripTouch) { touching = false; idle = 0 }
    public func touchCancelled(_ t: StripTouch) { touching = false }
}
