import AppKit

/// One chip per running coding agent. A chip pulses when that agent is waiting for you; tap it to bring its
/// window or tab to the front. Hidden while nothing is running. Long-press (or the "+n" chip) opens the Agents mode.
final class AgentsWidget: Widget {
    static let chip: CGFloat = 26
    static let gap: CGFloat = 2
    static let pad: CGFloat = 4
    static let maxChips = 5

    private var chips: [(frame: CGRect, agent: Agent?)] = []

    private func shown(_ agents: [Agent]) -> (chips: [Agent], overflow: Int) {
        if agents.count <= Self.maxChips { return (agents, 0) }
        return (Array(agents.prefix(Self.maxChips - 1)), agents.count - (Self.maxChips - 1))
    }

    var animating: Bool { AgentMonitor.shared.agents.contains { $0.needsYou } }

    func width(_ ctx: ModeContext) -> CGFloat {
        let agents = AgentMonitor.shared.agents
        guard !agents.isEmpty else { return 0 }
        let (list, overflow) = shown(agents)
        let n = CGFloat(list.count) + (overflow > 0 ? 1 : 0)
        return Self.pad * 2 + n * Self.chip + (n - 1) * Self.gap
    }

    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        let agents = AgentMonitor.shared.agents
        chips = []
        guard !agents.isEmpty else { return }
        let theme = c.theme
        let anyWaiting = agents.contains { $0.needsYou }
        let pulse = CGFloat(0.5 + 0.5 * sin(c.time * 5))
        if anyWaiting {
            c.glowing(theme.bad, blur: 8, strength: 0.35 + 0.45 * pulse) { tile(c, r, pressed: pressed) }
        } else {
            tile(c, r, pressed: pressed)
        }
        let (list, overflow) = shown(agents)
        var x = r.minX + Self.pad
        for a in list {
            let f = CGRect(x: x, y: r.minY, width: Self.chip, height: r.height)
            chips.append((f, a))
            drawChip(c, a, in: f, pulse: pulse)
            x += Self.chip + Self.gap
        }
        if overflow > 0 {
            let f = CGRect(x: x, y: r.minY, width: Self.chip, height: r.height)
            chips.append((f, nil))
            c.roundRect(f.insetBy(dx: 2, dy: 4), radius: 5, fill: theme.surfaceHi)
            c.text("+\(overflow)", x: f.midX, size: 9.5, color: theme.dim, weight: .bold, align: .center)
        }
    }

    private func drawChip(_ c: Canvas, _ a: Agent, in f: CGRect, pulse: CGFloat) {
        let theme = c.theme
        let brand = theme.tint(NSColor(hex: a.color))
        let side: CGFloat = 18
        let icon = CGRect(x: f.midX - side / 2, y: f.midY - side / 2 + 0.5, width: side, height: side)
        if a.needsYou {
            let wash = theme.surface.mix(theme.bad, 0.35 + 0.3 * pulse)
            c.glowing(theme.bad, blur: 6, strength: 0.4 + 0.6 * pulse) {
                c.roundRect(f.insetBy(dx: 1, dy: 2.5), radius: 6, fill: wash, stroke: theme.bad.withAlphaComponent(0.5 + 0.4 * pulse), lineWidth: 1)
            }
        } else if a.state == .working {
            c.roundRect(f.insetBy(dx: 1, dy: 2.5), radius: 6, fill: theme.surfaceHi.withAlphaComponent(0.6))
        }
        if let spec = a.logo, let logo = LogoCache.shared.logo(spec) {
            c.faded(a.state == .idle ? 0.75 : 1) { c.image(logo.image, in: icon, radius: logo.isAppIcon ? 0 : side * 0.24) }
        } else {
            c.roundRect(icon, radius: side * 0.24, fill: brand.withAlphaComponent(a.state == .idle ? 0.55 : 0.9))
            c.symbol(a.icon, in: icon, color: theme.on(brand), pointSize: 9)
        }
        // Status dot at the bottom-right corner of the icon.
        let dot = CGPoint(x: icon.maxX - 1, y: icon.minY + 1)
        switch a.state {
        case .waiting:
            c.glowing(theme.bad, blur: 5, strength: 1) {
                c.circle(center: dot, radius: 3.6, theme.background)
                c.circle(center: dot, radius: 2.6 + 0.6 * pulse, theme.bad)
            }
        case .working:
            let breathe = CGFloat(0.6 + 0.4 * sin(c.time * 2.2))
            c.circle(center: dot, radius: 3.2, theme.background)
            c.circle(center: dot, radius: 2.2, theme.accent2.withAlphaComponent(breathe))
        case .idle:
            c.circle(center: dot, radius: 3, theme.background)
            c.circle(center: dot, radius: 1.8, theme.dim.withAlphaComponent(0.7))
        }
    }

    func tap(_ ctx: ModeContext) { ctx.switchMode("agents") }

    func tap(_ ctx: ModeContext, at x: CGFloat) {
        guard let hit = chips.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) else { ctx.switchMode("agents"); return }
        guard let a = hit.agent else { ctx.switchMode("agents"); return }
        Self.focus(a, ctx)
    }

    func longPress(_ ctx: ModeContext) { ctx.switchMode("agents") }

    static func focus(_ a: Agent, _ ctx: ModeContext) {
        ctx.toast("→ \(a.name)  ·  \(a.detail)")
        AgentMonitor.shared.focus(a) { ok in
            if !ok { ctx.toast("Couldn't find the exact tab — opened \(a.name)'s app instead") }
        }
    }

}
