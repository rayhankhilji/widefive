import AppKit

/// Every coding agent on the Mac as a quiet list of cards: mark, "Claude Code 2", project · branch, and one status line
/// ("Needs input · Approve: swift test", "Running npm test", "Done · All tests pass"). Tap a card to bring that
/// session to the front; long-press to mark it seen.
public final class AgentsMode: StripMode, DemoStartable {
    public let id = "agents"
    public let title = "Agents"
    public let icon = "rectangle.stack"
    public var refreshInterval: Double { 0.5 }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }
    public var isAnimated: Bool {
        scroller.animating || presses.animating || age < 0.4 || agents.contains { $0.state == .working || $0.state == .waiting }
    }

    private var ctx: ModeContext?
    private var agents: [Agent] = []
    private var frames: [(String, CGRect)] = []
    private var pressed: String?
    private let presses = Presses<String>()
    private var scroller = Scroller()
    private var work: DispatchWorkItem?
    private var longFired = false
    private var age = 0.0

    static let markSize: CGFloat = 16
    static let nameSize: CGFloat = 11
    static let metaSize: CGFloat = 10

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

    // MARK: Layout

    private func statusParts(_ a: Agent) -> (String, String?) {
        let label = a.stateLabel
        let line = a.statusLine
        if a.state == .working { return (line, nil) }
        if line == label || line.isEmpty { return (label, nil) }
        return (label, line)
    }

    private func cardWidth(_ a: Agent) -> CGFloat {
        let name = Canvas.measure(a.displayName, size: Self.nameSize, weight: .semibold)
        let place = Canvas.measure(a.whereLine, size: Self.metaSize)
        let (head, tail) = statusParts(a)
        let status = Canvas.measure(head, size: Self.metaSize, weight: .medium) + (tail.map { Canvas.measure(" · " + $0, size: Self.metaSize) } ?? 0) + 11
        let time = Canvas.measure(AgentStyle.elapsed(since: a.since), size: 9.5, mono: true)
        let text = max(name + 6 + min(place, 120), status)
        return min(350, max(200, 12 + AgentStyle.markWidth(a.mark, height: Self.markSize) + 9 + text + 12 + time + 10))
    }

    // MARK: Drawing

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        frames = []
        let hint = AgentMonitor.shared.hint

        if agents.isEmpty {
            if let hint {
                let w = min(c.width - x0 - 8, Canvas.measure(hint.text, size: 11, weight: .medium) + 40)
                let r = CGRect(x: x0, y: 2, width: w, height: c.height - 4)
                frames.append(("hint", r))
                drawHint(c, hint, r)
                return
            }
            c.text("No coding agents running", x: x0 + 2, size: 11.5, color: theme.text.withAlphaComponent(0.85), weight: .medium)
            let w = Canvas.measure("No coding agents running", size: 11.5, weight: .medium)
            c.text("Claude Code, Codex, Cursor and web agents show up here on their own.", x: x0 + w + 14, size: 10.5, color: theme.dim,
                   maxWidth: c.width - x0 - w - 20)
            return
        }

        // Header: a plain count, the way a list would title itself.
        let blocked = agents.filter { $0.state == .waiting }.count
        let finished = agents.filter { $0.state == .done }.count
        var summary = "\(agents.count) \(agents.count == 1 ? "session" : "sessions")"
        if blocked > 0 { summary = "\(blocked) need\(blocked == 1 ? "s" : "") input" } else if finished > 0 { summary = "\(finished) done" }
        c.text("Agents", x: x0 + 2, y: 15, size: 11, color: theme.text, weight: .semibold)
        c.text(summary, x: x0 + 2, y: 3.5, size: 9.5, color: blocked > 0 ? AgentStyle.textColor(.waiting, theme) : theme.dim, weight: .medium)
        let headerW = max(Canvas.measure("Agents", size: 11, weight: .semibold), Canvas.measure(summary, size: 9.5, weight: .medium)) + 14

        let listX = x0 + headerW
        var widths = agents.map(cardWidth)
        if let hint { widths.append(min(320, Canvas.measure(hint.text, size: 10) + 40)) }
        let gap: CGFloat = 6
        let total = widths.reduce(0) { $0 + $1 + gap }
        scroller.maxOffset = max(0, total - (c.width - listX))
        let off = scroller.offset
        let view = CGRect(x: listX - 2, y: 0, width: c.width - listX + 2, height: c.height)
        let appear = CGFloat(Ease.outCubic(age / 0.35))
        c.clip(view) {
            c.fadeEdges(view, left: off > 1 ? 16 : 0, right: off < scroller.maxOffset - 1 ? 24 : 0) {
                c.faded(appear) {
                    var x = listX - off
                    for (i, a) in agents.enumerated() {
                        let r = CGRect(x: x, y: 2, width: widths[i], height: c.height - 4)
                        frames.append((a.id, r))
                        if r.maxX > view.minX, r.minX < view.maxX { drawCard(c, a, r) }
                        x += widths[i] + gap
                    }
                    if let hint {
                        let r = CGRect(x: x, y: 2, width: widths[agents.count], height: c.height - 4)
                        frames.append(("hint", r))
                        drawHint(c, hint, r)
                    }
                }
            }
        }
        if scroller.maxOffset > 0 {
            let visible = c.width - listX
            let bw = max(24, visible * visible / (visible + scroller.maxOffset))
            let bx = listX + max(0, min(1, off / scroller.maxOffset)) * (visible - bw)
            c.roundRect(CGRect(x: bx, y: 0.5, width: bw, height: 1), radius: 0.5, fill: theme.text.withAlphaComponent(scroller.animating ? 0.35 : 0.12))
        }
    }

    private func drawCard(_ c: Canvas, _ a: Agent, _ r: CGRect) {
        let theme = c.theme
        let p = presses.amount(a.id)
        c.scaled(1 - 0.025 * p, around: CGPoint(x: r.midX, y: r.midY)) {
            AgentStyle.card(c, r, pressed: p)
            if a.alerting {
                // A thin inset edge in the status colour: the only colour on a card besides its dot.
                c.roundRect(CGRect(x: r.minX + 4, y: r.minY + 6, width: 2, height: r.height - 12), radius: 1, fill: AgentStyle.color(a.state, theme))
            }
            let dim = a.state == .idle
            let mw = AgentStyle.markWidth(a.mark, height: Self.markSize)
            let markRect = CGRect(x: r.minX + 12, y: r.midY - Self.markSize / 2, width: mw, height: Self.markSize)
            AgentStyle.mark(c, a.mark, in: markRect, alpha: dim ? 0.5 : 1)

            let textX = markRect.maxX + 9
            let time = AgentStyle.elapsed(since: a.since)
            let timeW = Canvas.measure(time, size: 9.5, mono: true)
            let right = r.maxX - 10
            let textW = right - timeW - 10 - textX

            // Line 1: "Claude Code 2  widefive · main"                         "4m"
            let nameColor = theme.text.withAlphaComponent(dim ? 0.55 : 0.95)
            let nw = c.text(a.displayName, x: textX, y: 14.5, size: Self.nameSize, color: nameColor, weight: .semibold, maxWidth: textW)
            if nw + 6 < textW {
                c.text(a.whereLine, x: textX + nw + 6, y: 15, size: Self.metaSize, color: theme.dim.withAlphaComponent(dim ? 0.6 : 0.9),
                       maxWidth: textW - nw - 6)
            }
            c.text(time, x: right, y: 15, size: 9.5, color: theme.dim.withAlphaComponent(0.8), mono: true, align: .right)

            // Line 2: "● Needs input · Approve: swift test"
            let lineY: CGFloat = 3.5
            AgentStyle.status(c, a.state, at: CGPoint(x: textX + 3, y: lineY + 6.5), size: 6)
            let (head, tail) = statusParts(a)
            let sx = textX + 11
            let headColor = a.alerting ? AgentStyle.textColor(a.state, theme) : theme.text.withAlphaComponent(dim ? 0.5 : 0.75)
            let hw = c.text(head, x: sx, y: lineY, size: Self.metaSize, color: headColor, weight: .medium, maxWidth: right - sx)
            if let tail, sx + hw + 4 < right {
                c.text(" · " + tail, x: sx + hw, y: lineY, size: Self.metaSize, color: theme.dim, maxWidth: right - sx - hw)
            }
        }
    }

    private func drawHint(_ c: Canvas, _ hint: AgentMonitor.Hint, _ r: CGRect) {
        let theme = c.theme
        AgentStyle.card(c, r, pressed: presses.amount("hint"))
        c.circle(center: CGPoint(x: r.minX + 12, y: r.midY), radius: 3, AgentStyle.amber)
        c.text("Finish setup", x: r.minX + 22, y: 14.5, size: 11, color: theme.text, weight: .semibold, maxWidth: r.width - 30)
        c.text(hint.text, x: r.minX + 22, y: 3.5, size: 10, color: theme.dim, maxWidth: r.width - 30)
    }

    // MARK: Touch

    private func hit(_ x: CGFloat) -> String? { frames.first { $0.1.minX <= x && x <= $0.1.maxX }?.0 }

    public func touchBegan(_ t: StripTouch) {
        scroller.begin(t)
        pressed = hit(t.x)
        longFired = false
        work?.cancel()
        guard let id = pressed else { return }
        presses.press(id)
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == id, id != "hint", !self.scroller.dragging else { return }
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
        guard !wasDragging, !longFired, let id = pressed, let ctx else { return }
        if id == "hint" {
            if let h = AgentMonitor.shared.hint, let url = URL(string: h.settingsURL) { NSWorkspace.shared.open(url) }
            if !AXIsProcessTrusted() { Keys.ensureAccessibility(prompt: true) }
            return
        }
        guard let a = agents.first(where: { $0.id == id }) else { return }
        AgentsWidget.focus(a, ctx)
    }
}
