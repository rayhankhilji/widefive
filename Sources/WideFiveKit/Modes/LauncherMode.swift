import AppKit

/// Mode switcher: one neon tile per mode.
public final class LauncherMode: StripMode {
    public let id = "launcher"
    public let title = "Modes"
    public let icon = "square.grid.2x2.fill"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private weak var registry: ModeRegistry?
    private var ctx: ModeContext?
    private var frames: [(String, CGRect)] = []
    private var pressed: String?
    private var age: Double = 0
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastX: CGFloat = 0
    private var lastT: Double = 0
    private var scrolling = false
    private var maxOffset: CGFloat = 0

    public init(registry: ModeRegistry) { self.registry = registry }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx; age = 0 }
    public func update(dt: Double) {
        age += dt
        // Momentum scrolling after a flick.
        if !scrolling, abs(velocity) > 5 {
            offset = max(0, min(maxOffset, offset - velocity * CGFloat(dt)))
            velocity *= CGFloat(pow(0.04, dt))
        }
    }

    private var entries: [StripMode] { registry?.modes.filter { $0.id != id } ?? [] }

    public func draw(_ c: Canvas) {
        let list = entries
        let x0 = StripController.exitWidth + 4
        let gap: CGFloat = 5
        let w: CGFloat = 112
        maxOffset = max(0, CGFloat(list.count) * (w + gap) - (c.width - x0))
        offset = min(offset, maxOffset)
        let appear = min(1, age / 0.25)
        frames = []
        for (i, m) in list.enumerated() {
            let delay = Double(i) * 0.03
            let a = CGFloat(max(0, min(1, (appear * 1.6 - delay))))
            let r = CGRect(x: x0 + CGFloat(i) * (w + gap) - offset, y: 0, width: w, height: 30).offsetBy(dx: 0, dy: -(1 - a) * 30)
            frames.append((m.id, r))
            guard r.maxX > x0, r.minX < c.width else { continue }
            let hue = CGFloat(i) / CGFloat(list.count) + CGFloat(c.time * 0.05)
            let isPressed = pressed == m.id
            c.gradient(r, [NSColor.hsb(hue, 0.85, isPressed ? 1 : 0.55), NSColor.hsb(hue + 0.08, 0.9, isPressed ? 0.8 : 0.3)], horizontal: true, radius: 6)
            c.symbol(m.icon, in: CGRect(x: r.minX + 4, y: r.minY, width: 20, height: 30), color: .white, pointSize: 12)
            c.text(m.title, x: r.minX + 26, y: r.minY + 8, size: 11, color: .white, weight: .semibold, maxWidth: r.width - 28)
        }
        if maxOffset > 0 {
            let visible = c.width - x0
            let total = visible + maxOffset
            c.fill(CGRect(x: x0 + offset / total * visible, y: 0, width: visible * visible / total, height: 1.5), NSColor(white: 1, alpha: 0.6))
        }
    }

    private func hit(_ x: CGFloat) -> String? { frames.first { $0.1.minX <= x && x <= $0.1.maxX }?.0 }

    public func touchBegan(_ t: StripTouch) {
        pressed = hit(t.x); scrolling = false; velocity = 0
        startOffset = offset; lastX = t.x; lastT = t.time
    }
    public func touchMoved(_ t: StripTouch) {
        if abs(t.dx) > 8 { scrolling = true; pressed = nil }
        guard scrolling else { return }
        offset = max(0, min(maxOffset, startOffset - t.dx))
        let dt = t.time - lastT
        if dt > 0 { velocity = (t.x - lastX) / CGFloat(dt) }
        lastX = t.x; lastT = t.time
    }
    public func touchEnded(_ t: StripTouch) {
        if !scrolling, let id = hit(t.x), id == pressed { ctx?.switchMode(id) }
        if !scrolling || t.time - lastT > 0.08 { velocity = 0 }
        scrolling = false
        pressed = nil
    }
}
