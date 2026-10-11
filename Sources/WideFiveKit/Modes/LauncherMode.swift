import AppKit

/// Mode switcher: themed tiles grouped into Tools and Games, staggered entrance, momentum scrolling.
public final class LauncherMode: StripMode {
    public let id = "launcher"
    public let title = "Modes"
    public let icon = "square.grid.2x2.fill"
    public var isAnimated: Bool { age < 1.4 || scroller.animating || presses.animating }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private weak var registry: ModeRegistry?
    private var ctx: ModeContext?
    private var frames: [(String, CGRect)] = []
    private var pressed: String?
    private let presses = Presses<String>()
    private var scroller = Scroller()
    private var age: Double = 0

    static let tileWidth: CGFloat = 110

    public init(registry: ModeRegistry) {
        self.registry = registry
        if registry.mode("themes") == nil { registry.register(ThemesMode()) }
    }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx; age = 0; presses.cancelAll() }
    public func update(dt: Double) {
        age += dt
        presses.step(dt)
        scroller.step(dt)
    }

    private var sections: [(String, [StripMode])] {
        let list = registry?.modes.filter { $0.id != id } ?? []
        return [("Tools", list.filter { !$0.isGame }), ("Games", list.filter { $0.isGame })].filter { !$0.1.isEmpty }
    }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        let gap = Metrics.gap
        let w = Self.tileWidth
        let secs = sections
        let count = secs.reduce(0) { $0 + $1.1.count }
        let headerW: CGFloat = 46

        var total: CGFloat = 0
        for (_, ms) in secs { total += headerW + CGFloat(ms.count) * (w + gap) }
        total += 4
        scroller.maxOffset = max(0, total - (c.width - x0))
        let off = scroller.offset
        let view = CGRect(x: x0 - 2, y: 0, width: c.width - x0 + 2, height: c.height)

        frames = []
        c.clip(view) {
            c.fadeEdges(view, left: off > 1 ? 22 : 0, right: off < scroller.maxOffset - 1 ? 34 : 0) {
                var x = x0 - off
                var i = 0
                for (name, ms) in secs {
                    let ha = CGFloat(Ease.outCubic((age - Double(i) * 0.026) / 0.4))
                    c.faded(ha) {
                        c.caption(name, x: x + headerW / 2 - 3, y: 15, color: theme.dim, align: .center)
                        c.fill(CGRect(x: x + headerW / 2 - 10, y: 11, width: 14, height: 1.5), theme.accent.withAlphaComponent(0.8))
                    }
                    x += headerW
                    for m in ms {
                        let r = CGRect(x: x, y: 2, width: w, height: c.height - 4)
                        frames.append((m.id, r))
                        if r.maxX > view.minX, r.minX < view.maxX {
                            drawTile(c, m, r, index: i, count: count)
                        }
                        x += w + gap
                        i += 1
                    }
                }
            }
        }
        if scroller.maxOffset > 0 {
            let visible = c.width - x0
            let all = visible + scroller.maxOffset
            let bw = max(24, visible * visible / all)
            let bx = x0 + max(0, min(1, off / scroller.maxOffset)) * (visible - bw)
            let a: CGFloat = scroller.animating ? 0.75 : 0.28
            c.roundRect(CGRect(x: bx, y: 0.5, width: bw, height: 1.5), radius: 0.75, fill: theme.accent.withAlphaComponent(a))
        }
    }

    private func drawTile(_ c: Canvas, _ m: StripMode, _ r: CGRect, index i: Int, count: Int) {
        let theme = c.theme
        let a = Ease.clamp((age - Double(i) * 0.026) / 0.5)
        let e = CGFloat(Ease.outBack(a, 1.5))
        let alpha = CGFloat(min(1, a * 2.2))
        let t = 0.5 - 0.5 * cos(CGFloat(i) * 0.62)
        let chipCol = theme.accent.mix(theme.accent2, t)
        c.faded(alpha) {
            c.translated(0, -(1 - e) * 16) {
                c.button(r, style: .plain, pressed: presses.amount(m.id)) { fg in
                    let chip = CGRect(x: r.minX + 4, y: r.midY - 9.5, width: 19, height: 19)
                    let cr = max(3, min(6, theme.radius * 0.75))
                    c.glowing(chipCol, blur: 6, strength: 0.6) {
                        c.gradient(chip, [chipCol.mix(.white, 0.18), chipCol.mix(.black, 0.18)], radius: cr)
                    }
                    c.symbol(m.icon, in: chip, color: theme.on(chipCol), pointSize: 10)
                    c.text(m.title, x: chip.maxX + 7, size: Metrics.Font.label, color: fg, weight: .semibold, maxWidth: r.maxX - chip.maxX - 11)
                }
            }
        }
    }

    private func hit(_ x: CGFloat) -> String? {
        guard x >= Metrics.contentX - 2 else { return nil }
        return frames.first { $0.1.minX <= x && x <= $0.1.maxX }?.0
    }

    public func touchBegan(_ t: StripTouch) {
        scroller.begin(t)
        pressed = hit(t.x)
        if let p = pressed { presses.press(p) }
    }
    public func touchMoved(_ t: StripTouch) {
        if scroller.move(t), pressed != nil { pressed = nil; presses.cancelAll() }
    }
    public func touchEnded(_ t: StripTouch) {
        let wasDragging = scroller.dragging
        scroller.end(t)
        if let p = pressed { presses.release(p) }
        if !wasDragging, let id = hit(t.x), id == pressed { ctx?.switchMode(id) }
        pressed = nil
    }
    public func touchCancelled(_ t: StripTouch) { scroller.end(t); pressed = nil; presses.cancelAll() }
}
