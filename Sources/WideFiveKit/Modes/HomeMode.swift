import AppKit

/// Per-app layout: leading items + the frontmost app's items (or defaults) + flexible gap + trailing widgets.
public final class HomeMode: StripMode {
    public let id = "home"
    public let title = "Home"
    public let icon = "house.fill"
    public var refreshInterval: Double { 0.5 }
    public var isAnimated: Bool { pressed != nil || hasMarquee }

    struct Slot {
        var item: Item
        var widget: Widget?
        var frame: CGRect = .zero
        var scrolls: Bool
    }

    private var ctx: ModeContext?
    private var slots: [Slot] = []
    private var builtFor: String?
    private var builtConfig: Config?
    private var pressed: Int?
    private var pressTouch: StripTouch?
    private var longPressFired = false
    private var longPressWork: DispatchWorkItem?
    private var scrollOffset: CGFloat = 0
    private var scrollStart: CGFloat = 0
    private var scrolling = false
    private var middleRange: (CGFloat, CGFloat) = (0, 0)
    private var contentWidth: CGFloat = 0
    private var widgetCache: [String: Widget] = [:]
    private var hasMarquee: Bool { slots.contains { $0.widget is NowPlayingWidget } && NowPlaying.shared.isPlaying }

    public init() {}

    public func activate(_ ctx: ModeContext) { self.ctx = ctx; rebuild() }

    public func rebuild() {
        guard let ctx else { return }
        let cfg = ctx.config
        let layout = cfg.layout(for: ctx.frontmostBundleId)
        let middle = (layout?.items.isEmpty == false) ? layout!.items : cfg.defaultItems
        func make(_ i: Item, scrolls: Bool) -> Slot {
            var w: Widget?
            if i.kind == "widget", let n = i.name {
                let key = "\(n)#\(i.width ?? 0)"
                w = widgetCache[key] ?? WidgetFactory.make(n, width: i.width.map { CGFloat($0) })
                widgetCache[key] = w
            }
            return Slot(item: i, widget: w, scrolls: scrolls)
        }
        slots = cfg.leading.map { make($0, scrolls: false) } + middle.map { make($0, scrolls: true) } + cfg.trailing.map { make($0, scrolls: false) }
        builtFor = ctx.frontmostBundleId
        builtConfig = cfg
        scrollOffset = 0
    }

    private func naturalWidth(_ s: Slot, _ ctx: ModeContext) -> CGFloat {
        if let w = s.item.width, s.item.kind != "widget" { return CGFloat(w) }
        switch s.item.kind {
        case "widget":
            guard let w = s.widget else { return 0 }
            let nat = w.width(ctx)
            return nat == 0 ? 0 : (s.item.width.map { CGFloat($0) } ?? nat)
        case "spacer": return 8
        case "separator": return 2
        case "slider": return 150
        default:
            let hasIcon = s.item.icon != nil
            let t = s.item.title ?? ""
            let tw = t.isEmpty ? 0 : Canvas.measure(t, size: 12) + (hasIcon ? 6 : 0)
            return max(40, (hasIcon ? 18 : 0) + tw + 22)
        }
    }

    private func layout(_ width: CGFloat) {
        guard let ctx else { return }
        let gap: CGFloat = 5
        let lead = slots.indices.filter { !slots[$0].scrolls && $0 < (slots.firstIndex { $0.scrolls } ?? slots.count) }
        let mid = slots.indices.filter { slots[$0].scrolls }
        let trail = slots.indices.filter { !lead.contains($0) && !mid.contains($0) }
        var x: CGFloat = 0
        for i in lead {
            let w = naturalWidth(slots[i], ctx)
            slots[i].frame = CGRect(x: x, y: 0, width: w, height: 30)
            if w > 0 { x += w + gap }
        }
        var tx = width
        for i in trail.reversed() {
            let w = naturalWidth(slots[i], ctx)
            tx -= w
            slots[i].frame = CGRect(x: tx, y: 0, width: w, height: 30)
            if w > 0 { tx -= gap }
        }
        middleRange = (x + 4, tx - 4)
        var mx = middleRange.0 - scrollOffset
        for i in mid {
            let w = naturalWidth(slots[i], ctx)
            slots[i].frame = CGRect(x: mx, y: 0, width: w, height: 30)
            if w > 0 { mx += w + gap }
        }
        contentWidth = mx + scrollOffset - middleRange.0
    }

    public func update(dt: Double) {
        guard let ctx else { return }
        if builtFor != ctx.frontmostBundleId || builtConfig != ctx.config { rebuild() }
    }

    public func draw(_ c: Canvas) {
        guard let ctx else { return }
        layout(c.width)
        for (i, s) in slots.enumerated() where s.frame.width > 0 {
            let draw = { self.drawSlot(c, s, pressed: self.pressed == i, ctx: ctx) }
            if s.scrolls { c.clip(CGRect(x: middleRange.0, y: 0, width: middleRange.1 - middleRange.0, height: 30), draw) } else { draw() }
        }
        if contentWidth > middleRange.1 - middleRange.0 {
            let visible = middleRange.1 - middleRange.0
            let frac = visible / contentWidth
            let bar = CGRect(x: middleRange.0 + (scrollOffset / contentWidth) * visible, y: 0, width: visible * frac, height: 1.5)
            c.fill(bar, c.theme.accent.withAlphaComponent(0.7))
        }
    }

    private func drawSlot(_ c: Canvas, _ s: Slot, pressed: Bool, ctx: ModeContext) {
        let r = s.frame
        switch s.item.kind {
        case "widget": s.widget?.draw(c, in: r, pressed: pressed, ctx: ctx)
        case "separator": c.fill(CGRect(x: r.midX - 0.5, y: 6, width: 1, height: 18), c.theme.dim.withAlphaComponent(0.5))
        case "spacer": break
        case "slider": drawSlider(c, s, r)
        default:
            let base = s.item.color.map { NSColor(hex: $0) } ?? c.theme.button
            c.roundRect(r, radius: 6, fill: pressed ? base.blended(withFraction: 0.35, of: .white) ?? base : base)
            let title = s.item.title ?? ""
            if let icon = s.item.icon {
                if title.isEmpty {
                    c.symbol(icon, in: r, color: c.theme.text, pointSize: 13)
                } else {
                    let tw = Canvas.measure(title, size: 12)
                    let total = 18 + 6 + tw
                    let x0 = r.midX - total / 2
                    c.symbol(icon, in: CGRect(x: x0, y: 0, width: 18, height: 30), color: c.theme.text, pointSize: 12)
                    c.text(title, x: x0 + 24, size: 12, color: c.theme.text)
                }
            } else {
                c.text(title, x: r.midX, size: title.unicodeScalars.first?.properties.isEmoji == true && title.count <= 2 ? 16 : 12,
                       color: c.theme.text, align: .center, maxWidth: r.width - 8)
            }
        }
    }

    private func sliderValue(_ name: String?) -> Float {
        name == "brightness" ? SystemControl.brightness : SystemControl.volume
    }

    private func drawSlider(_ c: Canvas, _ s: Slot, _ r: CGRect) {
        c.roundRect(r, radius: 6, fill: c.theme.button)
        c.symbol(s.item.icon ?? "slider.horizontal.3", in: CGRect(x: r.minX + 2, y: 0, width: 22, height: 30), color: c.theme.text, pointSize: 11)
        let track = CGRect(x: r.minX + 28, y: r.midY - 2, width: r.width - 38, height: 4)
        let v = CGFloat(sliderValue(s.item.name))
        c.roundRect(track, radius: 2, fill: c.theme.dim.withAlphaComponent(0.35))
        c.gradient(CGRect(x: track.minX, y: track.minY, width: track.width * v, height: 4), [c.theme.accent, c.theme.accent2], horizontal: true, radius: 2)
        c.circle(center: CGPoint(x: track.minX + track.width * v, y: track.midY), radius: 6, .white)
    }

    private func setSlider(_ s: Slot, x: CGFloat) {
        let r = s.frame
        let v = Float(max(0, min(1, (x - (r.minX + 28)) / (r.width - 38))))
        if s.item.name == "brightness" { SystemControl.brightness = v } else { SystemControl.volume = v }
    }

    private func index(at x: CGFloat) -> Int? {
        slots.firstIndex { s in
            guard s.frame.width > 0, s.frame.minX <= x, x <= s.frame.maxX else { return false }
            return !s.scrolls || (x >= middleRange.0 && x <= middleRange.1)
        }
    }

    public func touchBegan(_ t: StripTouch) {
        pressed = index(at: t.x)
        pressTouch = t
        longPressFired = false
        scrolling = false
        scrollStart = scrollOffset
        longPressWork?.cancel()
        guard let i = pressed, let ctx else { return }
        if slots[i].item.kind == "slider" { setSlider(slots[i], x: t.x); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == i, !self.scrolling else { return }
            let s = self.slots[i]
            if let lp = s.item.longPress { ctx.run(lp); self.longPressFired = true }
            else if let w = s.widget { w.longPress(ctx); self.longPressFired = true }
            ctx.requestRedraw()
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    public func touchMoved(_ t: StripTouch) {
        guard let start = pressTouch else { return }
        if let i = pressed, slots[i].item.kind == "slider" { setSlider(slots[i], x: t.x); return }
        let inMiddle = start.startX >= middleRange.0 && start.startX <= middleRange.1
        let overflow = contentWidth - (middleRange.1 - middleRange.0)
        if inMiddle, overflow > 0, abs(t.dx) > 8 {
            scrolling = true
            pressed = nil
            scrollOffset = max(0, min(overflow, scrollStart - t.dx))
        }
    }

    public func touchEnded(_ t: StripTouch) {
        longPressWork?.cancel()
        defer { pressed = nil; pressTouch = nil }
        guard let i = pressed, !longPressFired, !scrolling, let ctx else { return }
        let s = slots[i]
        if s.item.kind == "slider" { return }
        if let w = s.widget {
            if abs(t.dx) > 30 { w.swipe(t.dx, ctx: ctx) } else if s.frame.contains(CGPoint(x: t.x, y: 15)) || abs(t.dx) < 12 { w.tap(ctx) }
        } else if let a = s.item.action, abs(t.dx) < 40 {
            ctx.run(a)
        }
    }

    public func touchCancelled(_ t: StripTouch) { longPressWork?.cancel(); pressed = nil; pressTouch = nil }
}
