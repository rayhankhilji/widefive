import AppKit

/// The look of everything agent-related: flat surfaces, hairlines, one small status dot, real marks. No glow, no
/// gradients, no emoji. Status colours are fixed (Radix-style 9 steps) so they read the same on every theme.
enum AgentStyle {
    static let amber = NSColor(hex: "#FFB224")   // needs input
    static let green = NSColor(hex: "#30A46C")   // done
    static let orange = NSColor(hex: "#F76B15")  // rate limited
    static let red = NSColor(hex: "#E5484D")     // error
    static let claude = NSColor(hex: "#D97757")  // Claude Code's mascot

    static func color(_ s: Agent.State, _ theme: Theme) -> NSColor {
        switch s {
        case .waiting: return amber
        case .done: return green
        case .limited: return orange
        case .failed: return red
        case .working: return theme.text.withAlphaComponent(0.75)
        case .idle: return theme.dim.withAlphaComponent(0.55)
        }
    }

    /// Hairline card: the one surface style used for chips and rows.
    static func card(_ c: Canvas, _ r: CGRect, pressed: CGFloat = 0, radius: CGFloat = 7) {
        let t = c.theme
        let base = t.isLight ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 1, alpha: 0.055 + 0.05 * pressed)
        let line = t.isLight ? NSColor(white: 0, alpha: 0.1) : NSColor(white: 1, alpha: 0.1 + 0.08 * pressed)
        c.roundRect(r.insetBy(dx: 0.25, dy: 0.25), radius: radius, fill: base, stroke: line, lineWidth: 0.5)
    }

    // MARK: Marks

    /// Clawd, Claude Code's mascot, exactly as its terminal banner draws it ("▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝"), 18×5 cells.
    static let clawd: [String] = [
        "000111111111111000",
        "000110111111011000",
        "011111111111111110",
        "000111111111111000",
        "000010100001010000",
    ]

    /// Draws an agent's mark centred in `r` (which should be about square). `alpha` dims idle agents.
    static func mark(_ c: Canvas, _ m: Agent.Mark, in r: CGRect, alpha: CGFloat = 1) {
        c.faded(alpha) {
            switch m {
            case .claudeCode: drawClawd(c, in: r)
            case .codex: drawCodex(c, in: r)
            case .appIcon(let bid):
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    let side = min(r.width, r.height) + 2
                    c.image(NSWorkspace.shared.icon(forFile: url.path), in: CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side))
                } else {
                    drawMonogram(c, "?", in: r)
                }
            case .monogram(let l): drawMonogram(c, l, in: r)
            }
        }
    }

    static func drawClawd(_ c: Canvas, in r: CGRect) {
        let cols = CGFloat(clawd[0].count), rows = CGFloat(clawd.count)
        let px = (min(r.width / cols, r.height / rows) * 2).rounded(.down) / 2   // whole half-points: crisp at 2x
        let w = cols * px, h = rows * px
        let x0 = (r.midX - w / 2).rounded(), y0 = (r.midY - h / 2 + px * 0.5).rounded()
        c.cg.setFillColor(claude.cgColor)
        for (ri, row) in clawd.enumerated() {
            for (ci, ch) in row.enumerated() where ch == "1" {
                c.cg.fill(CGRect(x: x0 + CGFloat(ci) * px, y: y0 + (rows - 1 - CGFloat(ri)) * px, width: px, height: px))
            }
        }
    }

    /// Codex: the ">_" prompt it greets you with, on a solid rounded square (black on white / white on black).
    static func drawCodex(_ c: Canvas, in r: CGRect) {
        let side = min(r.width, r.height)
        let box = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        let fg = c.theme.isLight ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        let bg = c.theme.isLight ? NSColor.white : NSColor(white: 0.06, alpha: 1)
        c.roundRect(box, radius: side * 0.26, fill: fg)
        // ">" as two strokes and "_" as a bar, drawn rather than typeset so it stays sharp at 16pt.
        let s = side / 16
        c.cg.saveGState()
        c.cg.setStrokeColor(bg.cgColor)
        c.cg.setLineWidth(1.6 * s)
        c.cg.setLineCap(.round)
        c.cg.setLineJoin(.round)
        c.cg.move(to: CGPoint(x: box.minX + 4.2 * s, y: box.minY + 11 * s))
        c.cg.addLine(to: CGPoint(x: box.minX + 7.4 * s, y: box.minY + 8 * s))
        c.cg.addLine(to: CGPoint(x: box.minX + 4.2 * s, y: box.minY + 5 * s))
        c.cg.strokePath()
        c.cg.move(to: CGPoint(x: box.minX + 8.8 * s, y: box.minY + 5 * s))
        c.cg.addLine(to: CGPoint(x: box.minX + 12 * s, y: box.minY + 5 * s))
        c.cg.strokePath()
        c.cg.restoreGState()
    }

    static func drawMonogram(_ c: Canvas, _ letter: String, in r: CGRect) {
        let side = min(r.width, r.height)
        let box = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        let t = c.theme
        c.roundRect(box, radius: side * 0.26, fill: t.isLight ? NSColor(white: 0, alpha: 0.06) : NSColor(white: 1, alpha: 0.1),
                    stroke: t.isLight ? NSColor(white: 0, alpha: 0.1) : NSColor(white: 1, alpha: 0.14), lineWidth: 0.5)
        c.text(letter, x: box.midX, y: box.minY + side * 0.2, size: side * 0.56, color: t.text.withAlphaComponent(0.85), weight: .semibold, align: .center)
    }

    // MARK: Status glyphs

    /// A status dot; needs-input breathes gently (opacity only), working is a thin spinner.
    static func status(_ c: Canvas, _ s: Agent.State, at p: CGPoint, size: CGFloat = 6) {
        let col = color(s, c.theme)
        switch s {
        case .working:
            spinner(c, at: p, radius: size / 2 + 0.5, color: col)
        case .waiting:
            let a = CGFloat(0.65 + 0.35 * (0.5 + 0.5 * sin(c.time * 3.2)))
            c.circle(center: p, radius: size / 2, col.withAlphaComponent(a))
        default:
            c.circle(center: p, radius: size / 2, col)
        }
    }

    static func spinner(_ c: Canvas, at p: CGPoint, radius: CGFloat, color: NSColor) {
        c.cg.saveGState()
        c.cg.setLineWidth(1.2)
        c.cg.setLineCap(.round)
        c.cg.setStrokeColor(color.withAlphaComponent(0.22).cgColor)
        c.cg.addArc(center: p, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        c.cg.strokePath()
        let a = CGFloat(c.time * 5).truncatingRemainder(dividingBy: .pi * 2)
        c.cg.setStrokeColor(color.cgColor)
        c.cg.addArc(center: p, radius: radius, startAngle: -a, endAngle: -a - .pi * 0.6, clockwise: true)
        c.cg.strokePath()
        c.cg.restoreGState()
    }

    /// "now", "45s", "12m", "3h", "2d"
    static func elapsed(since d: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 10 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
