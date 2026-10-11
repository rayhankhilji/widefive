import AppKit

/// Tap through every theme live: each swatch is drawn in its own palette, the bar crossfades on tap.
public final class ThemesMode: StripMode {
    public let id = "themes"
    public let title = "Themes"
    public let icon = "paintpalette.fill"
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }
    public var isAnimated: Bool { age < 1.2 || presses.animating || !select.settled }
    public var refreshInterval: Double { 1 }

    /// Wired by the controller: previews + persists a theme.
    public var pick: ((String) -> Void)?

    private var ctx: ModeContext?
    private var frames: [(String, CGRect)] = []
    private let presses = Presses<String>()
    private var pressed: String?
    private var age: Double = 0
    private var select = Smoothed(0, speed: 20)

    public init() {}

    public func activate(_ ctx: ModeContext) {
        self.ctx = ctx
        age = 0
        select.snap(Double(Theme.all.firstIndex { $0.name == ctx.theme.name } ?? 0))
    }

    public func update(dt: Double) { age += dt; presses.step(dt); select.step(dt) }

    public func draw(_ c: Canvas) {
        let x0 = Metrics.contentX
        let themes = Theme.all
        let gap: CGFloat = 4
        let w = floor((c.width - x0 - 2 - gap * CGFloat(themes.count - 1)) / CGFloat(themes.count))
        let current = themes.firstIndex { $0.name == c.theme.name } ?? 0
        select.target = Double(current)
        frames = []
        for (i, t) in themes.enumerated() {
            let r = CGRect(x: x0 + CGFloat(i) * (w + gap), y: 2, width: w, height: c.height - 4)
            frames.append((t.name, r))
            let a = Ease.clamp((age - Double(i) * 0.03) / 0.45)
            let e = CGFloat(Ease.outBack(a, 1.4))
            let p = presses.amount(t.name)
            c.faded(CGFloat(min(1, a * 2))) {
                c.translated(0, -(1 - e) * 14) {
                    c.scaled(1 - 0.06 * p, around: CGPoint(x: r.midX, y: r.midY)) { swatch(c, t, r, selected: i == current) }
                }
            }
        }
        // Sliding selection ring.
        let sx = x0 + CGFloat(select.value) * (w + gap)
        let ring = CGRect(x: sx - 1.5, y: 0.5, width: w + 3, height: c.height - 1)
        c.glowing(c.theme.accent, blur: 8, strength: 0.9) {
            c.roundRect(ring, radius: min(themes[current].radius, 9) + 1.5, fill: .clear, stroke: c.theme.accent, lineWidth: 1.5)
        }
    }

    private func swatch(_ c: Canvas, _ t: Theme, _ r: CGRect, selected: Bool) {
        let rad = min(t.radius, 9)
        if let top = t.backgroundTop { c.gradient(r, [top, t.background], radius: rad) } else { c.roundRect(r, radius: rad, fill: t.background) }
        c.roundRect(r.insetBy(dx: 0.25, dy: 0.25), radius: rad, fill: .clear,
                    stroke: t.isLight ? NSColor(white: 0, alpha: 0.12) : NSColor(white: 1, alpha: 0.12), lineWidth: 0.5)
        // Mini "button" in the theme's surface with its accent dot.
        let chip = CGRect(x: r.minX + 4, y: r.minY + 4, width: 16, height: r.height - 8)
        c.roundRect(chip, radius: min(rad, 5), fill: t.button)
        c.circle(center: CGPoint(x: chip.midX, y: chip.midY), radius: 3, t.accent)
        let tx = chip.maxX + 5
        c.text(t.displayName, x: tx, y: r.minY + 10, size: 9.5, color: t.text, weight: .semibold, maxWidth: r.maxX - tx - 3)
        let cols = [t.accent, t.accent2, t.good, t.warn, t.bad]
        for (k, col) in cols.enumerated() {
            c.roundRect(CGRect(x: tx + CGFloat(k) * 8, y: r.minY + 5, width: 6, height: 3), radius: 1.5, fill: col)
        }
        if selected {
            c.symbol("checkmark.circle.fill", in: CGRect(x: r.maxX - 14, y: r.minY + 5, width: 11, height: 11), color: t.accent, pointSize: 8)
        }
    }

    private func hit(_ x: CGFloat) -> String? { frames.first { $0.1.minX - 2 <= x && x <= $0.1.maxX + 2 }?.0 }

    public func touchBegan(_ t: StripTouch) { pressed = hit(t.x); if let p = pressed { presses.press(p) } }
    public func touchMoved(_ t: StripTouch) {
        // Scrub across swatches to preview.
        guard let h = hit(t.x), h != pressed else { return }
        if let p = pressed { presses.release(p) }
        pressed = h
        presses.press(h)
    }
    public func touchEnded(_ t: StripTouch) {
        if let p = pressed {
            presses.release(p)
            if p != ctx?.theme.name {
                pick?(p)
                ctx?.toast("🎨  \(Theme.named(p).displayName)")
            }
        }
        pressed = nil
    }
    public func touchCancelled(_ t: StripTouch) { pressed = nil; presses.cancelAll() }
}
