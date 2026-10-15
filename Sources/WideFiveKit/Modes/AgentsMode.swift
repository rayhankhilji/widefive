import AppKit

/// Every coding agent on the Mac as a row: logo, name, project/tab, and whether it's working or waiting for you.
/// Tap → bring its window/tab to the front. Long-press → mark as seen (stops the pulsing without switching).
public final class AgentsMode: StripMode, DemoStartable {
    public let id = "agents"
    public let title = "Agents"
    public let icon = "person.2.wave.2"
    public var refreshInterval: Double { 0.5 }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }
    public var isAnimated: Bool { scroller.animating || presses.animating || agents.contains { $0.needsYou } || age < 0.8 }

    private var ctx: ModeContext?
    private var agents: [Agent] = []
    private var frames: [(String, CGRect)] = []
    private var pressed: String?
    private let presses = Presses<String>()
    private var scroller = Scroller()
    private var work: DispatchWorkItem?
    private var longFired = false
    private var age = 0.0

    public init() {}

    public func activate(_ ctx: ModeContext) {
        self.ctx = ctx
        age = 0
        presses.cancelAll()
        agents = AgentMonitor.shared.agents
        AgentMonitor.shared.scan()
    }

    public func update(dt: Double) {
        age += dt
        presses.step(dt)
        scroller.step(dt)
        agents = AgentMonitor.shared.agents
    }

    public func startDemo() {
        AgentMonitor.shared.demoAgents = AgentMonitor.demoList()
        AgentMonitor.shared.scan()
        agents = AgentMonitor.shared.agents
    }

    private func rowWidth(_ a: Agent) -> CGFloat {
        let name = Canvas.measure(a.name, size: Metrics.Font.label, weight: .semibold)
        let sub = Canvas.measure(subtitle(a), size: Metrics.Font.caption + 0.5)
        let pill = pillWidth(a)
        return min(300, 30 + max(name, sub) + 10 + pill + 8)
    }

    private func subtitle(_ a: Agent) -> String {
        if a.needsYou, let m = a.message, !m.isEmpty { return m }
        return a.detail
    }

    private func pillText(_ a: Agent) -> String {
        switch a.state {
        case .waiting: return "needs you"
        case .working: return "working"
        case .idle: return a.signal == "seen" ? "seen" : "idle"
        }
    }

    private func pillWidth(_ a: Agent) -> CGFloat { Canvas.measure(pillText(a), size: 8, weight: .bold) + 14 + (a.state == .working ? 14 : 0) }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        frames = []
        if agents.isEmpty {
            let r = CGRect(x: x0, y: 1.5, width: 26, height: c.height - 3)
            c.panel(r)
            c.symbol("person.2.wave.2", in: r, color: theme.accent, pointSize: Metrics.iconSmall)
            let msg = AgentMonitor.shared.config.enabled ? "No coding agents running" : "Agent monitor is off (config → agents.enabled)"
            c.text(msg, x: r.maxX + 10, size: Metrics.Font.body, color: theme.text, weight: .medium)
            let tw = Canvas.measure(msg, size: Metrics.Font.body, weight: .medium)
            c.caption("Claude Code · Codex · Cursor · ChatGPT · Devin · web agents in Chrome & Safari", x: r.maxX + 22 + tw, maxWidth: c.width - (r.maxX + 26 + tw))
            return
        }
        let waiting = agents.filter { $0.needsYou }.count
        let summary = waiting > 0 ? "\(waiting) need\(waiting == 1 ? "s" : "") you" : "\(agents.count) running"
        let summaryW = Canvas.measure(summary, size: Metrics.Font.caption, weight: .bold) + 4
        let pulse = CGFloat(0.5 + 0.5 * sin(c.time * 5))
        c.caption(summary, x: x0, color: waiting > 0 ? theme.bad.mix(theme.text, 0.3 * (1 - pulse)) : theme.dim)
        let listX = x0 + summaryW + Metrics.groupGap
        let widths = agents.map(rowWidth)
        let total = widths.reduce(0) { $0 + $1 + Metrics.gap }
        scroller.maxOffset = max(0, total - (c.width - listX))
        let off = scroller.offset
        let view = CGRect(x: listX - 2, y: 0, width: c.width - listX + 2, height: c.height)
        c.clip(view) {
            c.fadeEdges(view, left: off > 1 ? 20 : 0, right: off < scroller.maxOffset - 1 ? 30 : 0) {
                var x = listX - off
                for (i, a) in agents.enumerated() {
                    let w = widths[i]
                    let r = CGRect(x: x, y: 1.5, width: w, height: c.height - 3)
                    frames.append((a.id, r))
                    if r.maxX > view.minX, r.minX < view.maxX {
                        let e = CGFloat(Ease.outCubic((age - Double(i) * 0.04) / 0.45))
                        c.faded(e) { c.translated(0, -(1 - e) * 10) { drawRow(c, a, r, pulse: pulse) } }
                    }
                    x += w + Metrics.gap
                }
            }
        }
        if scroller.maxOffset > 0 {
            let visible = c.width - listX
            let bw = max(24, visible * visible / (visible + scroller.maxOffset))
            let bx = listX + max(0, min(1, off / scroller.maxOffset)) * (visible - bw)
            c.roundRect(CGRect(x: bx, y: 0.5, width: bw, height: 1.5), radius: 0.75, fill: theme.accent.withAlphaComponent(scroller.animating ? 0.75 : 0.28))
        }
    }

    private func drawRow(_ c: Canvas, _ a: Agent, _ r: CGRect, pulse: CGFloat) {
        let theme = c.theme
        let brand = theme.tint(NSColor(hex: a.color))
        let style: ButtonStyle = a.needsYou ? .tinted(theme.bad) : .plain
        let p = presses.amount(a.id)
        let draw = {
            c.button(r, style: style, pressed: p) { fg in
                let side: CGFloat = 18
                let icon = CGRect(x: r.minX + 5, y: r.midY - side / 2, width: side, height: side)
                if let spec = a.logo, let logo = LogoCache.shared.logo(spec) {
                    c.image(logo.image, in: icon, radius: logo.isAppIcon ? 0 : side * 0.24)
                } else {
                    c.roundRect(icon, radius: side * 0.24, fill: brand)
                    c.symbol(a.icon, in: icon, color: theme.on(brand), pointSize: 9)
                }
                let pillW = self.pillWidth(a)
                let textX = icon.maxX + 7
                let textW = r.maxX - 8 - pillW - textX - 4
                c.text(a.name, x: textX, y: r.midY - 1, size: Metrics.Font.label, color: a.needsYou ? theme.text : fg, weight: .semibold, maxWidth: textW)
                c.text(self.subtitle(a), x: textX, y: r.minY + 1.5, size: Metrics.Font.caption + 0.5, color: a.needsYou ? theme.text.withAlphaComponent(0.85) : theme.dim, maxWidth: textW)
                let pill = CGRect(x: r.maxX - 6 - pillW, y: r.midY - 6.5, width: pillW, height: 13)
                let col: NSColor
                switch a.state {
                case .waiting: col = theme.bad
                case .working: col = theme.accent2
                case .idle: col = theme.dim
                }
                if a.needsYou {
                    c.glowing(col, blur: 5, strength: 0.4 + 0.6 * pulse) { c.roundRect(pill, radius: 6.5, fill: col) }
                } else {
                    c.roundRect(pill, radius: 6.5, fill: col.withAlphaComponent(theme.isLight ? 0.18 : 0.22))
                }
                if a.state == .working {
                    // Three tiny dots marching inside the pill.
                    for k in 0..<3 {
                        let ph = CGFloat(0.5 + 0.5 * sin(c.time * 4 - Double(k) * 0.9))
                        c.circle(center: CGPoint(x: pill.minX + 6 + CGFloat(k) * 4, y: pill.midY), radius: 1 + 0.5 * ph, col.withAlphaComponent(0.4 + 0.6 * ph))
                    }
                    c.text(self.pillText(a), x: pill.minX + 20, y: pill.minY + 2, size: 8, color: col, weight: .bold)
                } else {
                    c.text(self.pillText(a), x: pill.midX, y: pill.minY + 2, size: 8, color: a.needsYou ? theme.on(col) : col, weight: .bold, align: .center)
                }
            }
        }
        if a.needsYou { c.glowing(theme.bad, blur: 10, strength: 0.3 + 0.4 * pulse, draw) } else { draw() }
    }

    private func hit(_ x: CGFloat) -> String? { frames.first { $0.1.minX <= x && x <= $0.1.maxX }?.0 }

    public func touchBegan(_ t: StripTouch) {
        scroller.begin(t)
        pressed = hit(t.x)
        longFired = false
        work?.cancel()
        guard let id = pressed else { return }
        presses.press(id)
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == id, !self.scroller.dragging else { return }
            self.longFired = true
            AgentMonitor.shared.acknowledge(id)
            self.ctx?.toast("Marked as seen")
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    public func touchMoved(_ t: StripTouch) {
        if scroller.move(t), pressed != nil { pressed = nil; presses.cancelAll(); work?.cancel() }
    }

    public func touchCancelled(_ t: StripTouch) { work?.cancel(); scroller.end(t); pressed = nil; presses.cancelAll() }

    public func touchEnded(_ t: StripTouch) {
        work?.cancel()
        let wasDragging = scroller.dragging
        scroller.end(t)
        if let p = pressed { presses.release(p) }
        defer { pressed = nil }
        guard !wasDragging, !longFired, let id = pressed, let a = agents.first(where: { $0.id == id }), let ctx else { return }
        AgentsWidget.focus(a, ctx)
    }
}
