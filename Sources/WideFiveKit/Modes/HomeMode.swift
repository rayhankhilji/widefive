import AppKit

/// Per-app layout: leading items + the frontmost app's items (or defaults) + flexible gap + trailing widgets.
public final class HomeMode: StripMode {
    public let id = "home"
    public let title = "Home"
    public let icon = "house.fill"
    public var refreshInterval: Double { 0.5 }
    public var isAnimated: Bool { pressed != nil || hasMarquee || presses.animating || scroller.animating || sliders.values.contains { !$0.settled } }

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
    private var scroller = Scroller()
    private var scrolling: Bool { scroller.dragging }
    private let presses = Presses<Int>()
    private var sliders: [String: Smoothed] = [:]
    private var quickStart: Float = 0
    private var quickDragged = false
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
        scroller = Scroller()
        presses.cancelAll()
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
        var mx = middleRange.0 - scroller.offset
        for i in mid {
            let w = naturalWidth(slots[i], ctx)
            slots[i].frame = CGRect(x: mx, y: 0, width: w, height: 30)
            if w > 0 { mx += w + gap }
        }
        contentWidth = max(0, mx - gap + scroller.offset - middleRange.0)
        scroller.maxOffset = max(0, contentWidth - (middleRange.1 - middleRange.0))
    }

    public func update(dt: Double) {
        guard let ctx else { return }
        if builtFor != ctx.frontmostBundleId || builtConfig != ctx.config { rebuild() }
        presses.step(dt)
        scroller.step(dt)
        for k in sliders.keys { sliders[k]?.step(dt) }
    }

    public func draw(_ c: Canvas) {
        guard let ctx else { return }
        layout(c.width)
        for (i, s) in slots.enumerated() where s.frame.width > 0 && !s.scrolls {
            drawSlot(c, s, pressed: presses.amount(i), ctx: ctx)
        }
        let mid = CGRect(x: middleRange.0 - 1, y: 0, width: middleRange.1 - middleRange.0 + 2, height: c.height)
        let off = scroller.offset, maxOff = scroller.maxOffset
        c.clip(mid) {
            c.fadeEdges(mid, left: off > 1 ? 18 : 0, right: off < maxOff - 1 ? 26 : 0) {
                for (i, s) in slots.enumerated() where s.frame.width > 0 && s.scrolls && s.frame.maxX > mid.minX && s.frame.minX < mid.maxX {
                    drawSlot(c, s, pressed: presses.amount(i), ctx: ctx)
                }
            }
        }
        if maxOff > 0 {
            let visible = mid.width
            let bw = max(20, visible * visible / (visible + maxOff))
            let bx = mid.minX + max(0, min(1, off / maxOff)) * (visible - bw)
            c.roundRect(CGRect(x: bx, y: 0.5, width: bw, height: 1.5), radius: 0.75, fill: c.theme.accent.withAlphaComponent(scroller.animating ? 0.75 : 0.25))
        }
    }

    private func drawSlot(_ c: Canvas, _ s: Slot, pressed p: CGFloat, ctx: ModeContext) {
        let full = s.frame
        let r = full.insetBy(dx: 0, dy: 1.5)
        switch s.item.kind {
        case "widget":
            guard let w = s.widget else { return }
            c.scaled(1 - 0.05 * p, around: CGPoint(x: r.midX, y: r.midY)) {
                w.draw(c, in: r, pressed: p > 0.3, ctx: ctx)
            }
        case "separator": c.roundRect(CGRect(x: r.midX - 0.5, y: 8, width: 1, height: 14), radius: 0.5, fill: c.theme.dim.withAlphaComponent(0.3))
        case "spacer": break
        case "slider": drawSlider(c, s, r, pressed: p)
        case "quick": drawQuick(c, s, r, pressed: p)
        default:
            if let spec = s.item.image, let logo = LogoCache.shared.logo(spec) {
                c.button(r, style: .plain, pressed: p) { _ in
                    let side = min(r.height - (logo.isAppIcon ? 1 : 7), r.width - 8)
                    let rect = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
                    c.image(logo.image, in: rect, radius: logo.isAppIcon ? 0 : side * 0.24)
                }
                return
            }
            let style: ButtonStyle = s.item.color.map { .tinted(c.theme.tint(NSColor(hex: $0))) } ?? .plain
            let title = s.item.title ?? ""
            c.button(r, style: style, pressed: p) { fg in
                if let icon = s.item.icon {
                    if title.isEmpty {
                        c.symbol(icon, in: r, color: fg, pointSize: Metrics.icon)
                    } else {
                        let tw = Canvas.measure(title, size: 12, weight: .medium)
                        let total = 16 + 5 + tw
                        let x0 = r.midX - total / 2
                        c.symbol(icon, in: CGRect(x: x0, y: r.minY, width: 16, height: r.height), color: fg, pointSize: Metrics.iconSmall + 0.5)
                        c.text(title, x: x0 + 21, size: 12, color: c.theme.text, weight: .medium)
                    }
                } else {
                    let emoji = title.unicodeScalars.first?.properties.isEmoji == true && title.count <= 2
                    c.text(title, x: r.midX, size: emoji ? 16 : 12, color: c.theme.text, weight: .medium, align: .center, maxWidth: r.width - 8)
                }
            }
        }
    }

    private func drawQuick(_ c: Canvas, _ s: Slot, _ r: CGRect, pressed p: CGFloat) {
        let name = s.item.name ?? "volume"
        let key = "quick." + name
        let target = Double(QuickControl.value(name))
        if sliders[key] == nil { sliders[key] = Smoothed(target, speed: 24) }
        sliders[key]?.target = target
        let v = CGFloat(max(0, min(1, sliders[key]?.value ?? target)))
        c.button(r, style: .plain, pressed: p) { fg in
            c.symbol(QuickControl.icon(name, v: Float(v)), in: CGRect(x: r.minX, y: r.minY + 2.5, width: r.width, height: r.height - 2.5), color: fg, pointSize: Metrics.icon)
            let track = CGRect(x: r.minX + 10, y: r.minY + 3.5, width: r.width - 20, height: 2)
            c.roundRect(track, radius: 1, fill: c.theme.dim.withAlphaComponent(0.25))
            c.roundRect(CGRect(x: track.minX, y: track.minY, width: max(2, track.width * v), height: 2), radius: 1, fill: c.theme.accent)
        }
    }

    private func sliderValue(_ name: String?) -> Float {
        name == "brightness" ? SystemControl.brightness : SystemControl.volume
    }

    private func drawSlider(_ c: Canvas, _ s: Slot, _ r: CGRect, pressed p: CGFloat) {
        let key = s.item.name ?? "volume"
        let target = Double(sliderValue(s.item.name))
        if sliders[key] == nil { sliders[key] = Smoothed(target, speed: 24) }
        sliders[key]?.target = target
        let v = CGFloat(max(0, min(1, sliders[key]?.value ?? target)))
        c.panel(r)
        c.symbol(s.item.icon ?? "slider.horizontal.3", in: CGRect(x: r.minX + 3, y: r.minY, width: 22, height: r.height), color: c.theme.accent, pointSize: Metrics.iconSmall)
        let track = CGRect(x: r.minX + 28, y: r.midY - 2, width: r.width - 38, height: 4)
        c.meter(track, value: v)
        let knob = CGPoint(x: track.minX + track.width * v, y: track.midY)
        c.glowing(c.theme.accent, blur: 6, strength: 0.5 + 0.5 * p) {
            c.circle(center: knob, radius: 5.5 + 1.5 * p, c.theme.isLight ? .white : c.theme.text)
        }
        if c.theme.isLight { c.roundRect(CGRect(x: knob.x - 5.5 - 1.5 * p, y: knob.y - 5.5 - 1.5 * p, width: 11 + 3 * p, height: 11 + 3 * p), radius: 5.5 + 1.5 * p, fill: .clear, stroke: NSColor(white: 0, alpha: 0.15), lineWidth: 0.5) }
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
        scroller.begin(t)
        longPressWork?.cancel()
        guard let i = pressed, let ctx else { return }
        presses.press(i)
        if slots[i].item.kind == "slider" { setSlider(slots[i], x: t.x); return }
        if slots[i].item.kind == "quick" { quickStart = QuickControl.value(slots[i].item.name ?? "volume"); quickDragged = false; return }
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
        // Apple-style press-and-slide on a quick control adjusts it without opening the full slider.
        if let i = pressed, slots[i].item.kind == "quick" {
            if abs(t.dx) > 6 { quickDragged = true; QuickControl.set(slots[i].item.name ?? "volume", quickStart + Float(t.dx / 220)) }
            return
        }
        let inMiddle = start.startX >= middleRange.0 && start.startX <= middleRange.1
        if inMiddle, scroller.move(t), pressed != nil {
            pressed = nil
            presses.cancelAll()
            longPressWork?.cancel()
        }
    }

    public func touchEnded(_ t: StripTouch) {
        longPressWork?.cancel()
        let wasScrolling = scrolling
        scroller.end(t)
        if let i = pressed { presses.release(i) }
        defer { pressed = nil; pressTouch = nil }
        guard let i = pressed, !longPressFired, !wasScrolling, let ctx else { return }
        let s = slots[i]
        if s.item.kind == "slider" { return }
        if s.item.kind == "quick" {
            if !quickDragged { ctx.switchMode("adjust.\(s.item.name ?? "volume")") }
            return
        }
        if let w = s.widget {
            if abs(t.dx) > 30 { w.swipe(t.dx, ctx: ctx) } else if s.frame.contains(CGPoint(x: t.x, y: 15)) || abs(t.dx) < 12 { w.tap(ctx) }
        } else if let a = s.item.action, abs(t.dx) < 40 {
            ctx.run(a)
        }
    }

    public func touchCancelled(_ t: StripTouch) { longPressWork?.cancel(); scroller.end(t); presses.cancelAll(); pressed = nil; pressTouch = nil }
}
