import AppKit

/// Coding agents on the home bar: one hairline card, a cell per session (mark, number, status dot). The first session
/// that needs you also says so in words. Tap a cell to bring that session to the front; long-press for the full list.
final class AgentsWidget: Widget {
    static let maxCells = 4
    static let markSize: CGFloat = 16
    static let pad: CGFloat = 7

    private var cells: [(frame: CGRect, agent: Agent?)] = []

    var animating: Bool { AgentMonitor.shared.agents.contains { $0.state == .working || $0.state == .waiting } }

    private struct Cell { var agent: Agent?; var label: String?; var width: CGFloat }

    /// Layout shared by `width` and `draw`, so tap targets always match what's drawn.
    private func layout(_ agents: [Agent]) -> [Cell] {
        let shown = Array(agents.prefix(agents.count > Self.maxCells ? Self.maxCells - 1 : Self.maxCells))
        let overflow = agents.count - shown.count
        var labelled = false
        var out: [Cell] = []
        for a in shown {
            var w = Self.pad + Self.markSize + 4 + numberWidth(a) + 5 + 6 + Self.pad
            var label: String?
            if a.alerting, !labelled {
                label = a.stateLabel
                w += Canvas.measure(label!, size: 10, weight: .medium) + 5
                labelled = true
            }
            out.append(Cell(agent: a, label: label, width: w))
        }
        if overflow > 0 { out.append(Cell(agent: nil, label: "+\(overflow)", width: 30)) }
        return out
    }

    private func numberWidth(_ a: Agent) -> CGFloat { a.number > 0 ? Canvas.measure("\(a.number)", size: 10, weight: .semibold, mono: true) : 0 }

    func width(_ ctx: ModeContext) -> CGFloat {
        let agents = AgentMonitor.shared.agents
        guard !agents.isEmpty else { return AgentMonitor.shared.hint == nil ? 0 : 30 }
        return layout(agents).reduce(0) { $0 + $1.width }
    }

    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        let theme = c.theme
        let agents = AgentMonitor.shared.agents
        cells = []
        AgentStyle.card(c, r, pressed: pressed ? 1 : 0)
        guard !agents.isEmpty else {
            if AgentMonitor.shared.hint != nil {
                // Detection is missing a permission: one quiet amber dot; the Agents mode explains.
                c.circle(center: CGPoint(x: r.midX, y: r.midY), radius: 3, AgentStyle.amber)
            }
            return
        }
        var x = r.minX
        let list = layout(agents)
        for (i, cell) in list.enumerated() {
            let f = CGRect(x: x, y: r.minY, width: cell.width, height: r.height)
            cells.append((f, cell.agent))
            if i > 0 {
                c.fill(CGRect(x: f.minX, y: r.minY + 7, width: 0.5, height: r.height - 14),
                       theme.isLight ? NSColor(white: 0, alpha: 0.1) : NSColor(white: 1, alpha: 0.1))
            }
            if let a = cell.agent {
                drawCell(c, a, label: cell.label, in: f)
            } else {
                c.text(cell.label ?? "", x: f.midX, size: 10, color: theme.dim, weight: .medium, mono: true, align: .center)
            }
            x += cell.width
        }
    }

    private func drawCell(_ c: Canvas, _ a: Agent, label: String?, in f: CGRect) {
        let theme = c.theme
        var x = f.minX + Self.pad
        let markRect = CGRect(x: x, y: f.midY - Self.markSize / 2, width: Self.markSize, height: Self.markSize)
        AgentStyle.mark(c, a.mark, in: markRect, alpha: a.state == .idle ? 0.55 : 1)
        x += Self.markSize + 4
        if a.number > 0 {
            x += c.text("\(a.number)", x: x, size: 10, color: theme.text.withAlphaComponent(a.state == .idle ? 0.45 : 0.8), weight: .semibold, mono: true)
        }
        x += 5
        AgentStyle.status(c, a.state, at: CGPoint(x: x + 3, y: f.midY), size: 6)
        x += 6 + 5
        if let label {
            c.text(label, x: x, size: 10, color: theme.text.withAlphaComponent(0.85), weight: .medium)
        }
    }

    func tap(_ ctx: ModeContext) { ctx.switchMode("agents") }

    func tap(_ ctx: ModeContext, at x: CGFloat) {
        guard let hit = cells.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }), let a = hit.agent else {
            ctx.switchMode("agents"); return
        }
        Self.focus(a, ctx)
    }

    func longPress(_ ctx: ModeContext) { ctx.switchMode("agents") }

    static func focus(_ a: Agent, _ ctx: ModeContext) {
        AgentMonitor.shared.focus(a) { ok in
            if !ok { ctx.toast("Opened \(a.displayName) — couldn't pick the exact tab") }
        }
    }
}
