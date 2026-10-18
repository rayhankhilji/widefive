import AppKit

/// The look of everything agent-related: flat surfaces, hairlines, one small status dot, real marks. No glow, no
/// gradients, no emoji. Status colours are fixed (Radix-style 9 steps) so they read the same on every theme.
enum AgentStyle {
    static let amber = NSColor(hex: "#FFB224")   // needs input
    static let green = NSColor(hex: "#30A46C")   // done
    static let orange = NSColor(hex: "#F76B15")  // rate limited
    static let red = NSColor(hex: "#E5484D")     // error

    /// Status colour for dots and edges.
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

    /// Status colour for text: the deeper (step 11) shade on light themes so it stays readable on white.
    static func textColor(_ s: Agent.State, _ theme: Theme) -> NSColor {
        guard theme.isLight else { return color(s, theme) }
        switch s {
        case .waiting: return NSColor(hex: "#AD5700")
        case .done: return NSColor(hex: "#18794E")
        case .limited: return NSColor(hex: "#CC4E00")
        case .failed: return NSColor(hex: "#CD2B31")
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

    /// Every mark is square.
    static func markWidth(_ m: Agent.Mark, height: CGFloat = 16) -> CGFloat { height }

    /// Draws an agent's icon centred in `r`. `alpha` dims idle agents.
    static func mark(_ c: Canvas, _ m: Agent.Mark, in r: CGRect, alpha: CGFloat = 1) {
        let side = min(r.width, r.height)
        let box = CGRect(x: (r.midX - side / 2).rounded(), y: (r.midY - side / 2).rounded(), width: side, height: side)
        c.faded(alpha) {
            switch m {
            case .official(let key):
                if let img = AgentIcons.image(key) { c.image(img, in: box, radius: side * 0.23) } else { drawMonogram(c, "?", in: box) }
            case .appIcon(let bid):
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    // macOS app icons carry their own margin; draw them a touch larger so they match the full-bleed ones.
                    let big = box.insetBy(dx: -side * 0.1, dy: -side * 0.1)
                    c.image(NSWorkspace.shared.icon(forFile: url.path), in: big)
                } else {
                    drawMonogram(c, "?", in: box)
                }
            case .monogram(let l): drawMonogram(c, l, in: box)
            }
        }
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
