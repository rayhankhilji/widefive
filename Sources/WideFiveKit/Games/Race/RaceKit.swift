import AppKit

/// Fast RGBA colour for the racer's hot drawing paths (avoids NSColor blending per polygon).
struct RCol {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255; g = CGFloat((hex >> 8) & 0xFF) / 255; b = CGFloat(hex & 0xFF) / 255; self.a = a
    }
    static func gray(_ v: CGFloat, _ a: CGFloat = 1) -> RCol { RCol(r: v, g: v, b: v, a: a) }
    static let white = RCol(r: 1, g: 1, b: 1), black = RCol(r: 0, g: 0, b: 0), clear = RCol(r: 0, g: 0, b: 0, a: 0)
    static let p1 = RCol(0x21e6ff), p2 = RCol(0xff2bd6), gold = RCol(0xffc93c), go = RCol(0x3ddc84), red = RCol(0xff3b30)

    func mix(_ o: RCol, _ t: CGFloat) -> RCol {
        let t = max(0, min(1, t))
        return RCol(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t)
    }
    func light(_ t: CGFloat) -> RCol { mix(RCol(r: 1, g: 1, b: 1, a: a), t) }
    func dark(_ t: CGFloat) -> RCol { mix(RCol(r: 0, g: 0, b: 0, a: a), t) }
    func alpha(_ v: CGFloat) -> RCol { RCol(r: r, g: g, b: b, a: v) }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Thin CGContext helpers shared by the racer's renderer, car art and HUD.
struct Pen {
    let cg: CGContext

    func set(_ c: RCol) { cg.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
    func fill(_ r: CGRect, _ c: RCol) { set(c); cg.fill(r) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RCol) { set(c); cg.fill(CGRect(x: x, y: y, width: w, height: h)) }
    func poly(_ pts: [CGPoint], _ c: RCol) {
        guard pts.count > 2 else { return }
        set(c); cg.beginPath(); cg.addLines(between: pts); cg.closePath(); cg.fillPath()
    }
    func poly(_ xy: [(CGFloat, CGFloat)], _ c: RCol) { poly(xy.map { CGPoint(x: $0.0, y: $0.1) }, c) }
    /// Trapezoid between two horizontal spans (road strips, walls).
    func quad(_ ax: CGFloat, _ bx: CGFloat, _ y1: CGFloat, _ cx: CGFloat, _ dx: CGFloat, _ y2: CGFloat, _ c: RCol) {
        set(c); cg.beginPath()
        cg.move(to: CGPoint(x: ax, y: y1)); cg.addLine(to: CGPoint(x: bx, y: y1))
        cg.addLine(to: CGPoint(x: dx, y: y2)); cg.addLine(to: CGPoint(x: cx, y: y2))
        cg.closePath(); cg.fillPath()
    }
    func rrect(_ r: CGRect, _ rad: CGFloat, _ c: RCol) {
        set(c)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil))
        cg.fillPath()
    }
    func strokeRR(_ r: CGRect, _ rad: CGFloat, _ c: RCol, _ w: CGFloat) {
        cg.setStrokeColor(c.cg); cg.setLineWidth(w)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil))
        cg.strokePath()
    }
    func ellipse(_ r: CGRect, _ c: RCol) { set(c); cg.fillEllipse(in: r) }
    func circle(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat, _ c: RCol) { set(c); cg.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)) }
    func line(_ a: CGPoint, _ b: CGPoint, _ c: RCol, _ w: CGFloat, round: Bool = false) {
        cg.setStrokeColor(c.cg); cg.setLineWidth(w); cg.setLineCap(round ? .round : .butt)
        cg.beginPath(); cg.move(to: a); cg.addLine(to: b); cg.strokePath()
    }
    func polyline(_ pts: [CGPoint], _ c: RCol, _ w: CGFloat, closed: Bool = false) {
        guard pts.count > 1 else { return }
        cg.setStrokeColor(c.cg); cg.setLineWidth(w); cg.setLineJoin(.round); cg.setLineCap(.round)
        cg.beginPath(); cg.addLines(between: pts); if closed { cg.closePath() }; cg.strokePath()
    }
    func arc(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ a0: CGFloat, _ a1: CGFloat, _ c: RCol, _ w: CGFloat, cap: CGLineCap = .butt) {
        cg.setStrokeColor(c.cg); cg.setLineWidth(w); cg.setLineCap(cap)
        cg.beginPath(); cg.addArc(center: CGPoint(x: cx, y: cy), radius: rad, startAngle: a0, endAngle: a1, clockwise: a1 < a0); cg.strokePath()
    }
    /// Vertical gradient (first colour at the top) clipped to `path`, or to `r` when no path is given.
    func vgrad(_ r: CGRect, _ cols: [RCol], path: CGPath? = nil) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols.map { $0.cg } as CFArray, locations: nil) else { return }
        cg.saveGState()
        if let path { cg.addPath(path) } else { cg.addRect(r) }
        cg.clip()
        cg.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }
    func hgrad(_ r: CGRect, _ cols: [RCol]) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols.map { $0.cg } as CFArray, locations: nil) else { return }
        cg.saveGState(); cg.clip(to: r)
        cg.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.midY), end: CGPoint(x: r.maxX, y: r.midY), options: [])
        cg.restoreGState()
    }
    /// Soft radial glow (light blooms, shadows).
    func glow(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat, _ c: RCol, sx: CGFloat = 1, sy: CGFloat = 1, add: Bool = false) {
        guard rad > 0.05, let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.cg, c.alpha(0).cg] as CFArray, locations: [0, 1]) else { return }
        cg.saveGState()
        if add { cg.setBlendMode(.plusLighter) }
        cg.translateBy(x: x, y: y); cg.scaleBy(x: sx, y: sy)
        cg.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rad, options: [])
        cg.restoreGState()
    }
}

enum RK {
    static func clamp(_ v: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat { min(b, max(a, v)) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func easeOut(_ t: CGFloat) -> CGFloat { let t = clamp(t); return 1 - pow(1 - t, 3) }
    static func easeIn(_ t: CGFloat) -> CGFloat { let t = clamp(t); return t * t * t }
    static func easeInOut(_ t: CGFloat) -> CGFloat { let t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    static func easeOutBack(_ t: CGFloat) -> CGFloat {
        let t = clamp(t), c1: CGFloat = 1.9, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
    /// Frame-rate independent exponential approach.
    static func approach(_ v: CGFloat, _ target: CGFloat, _ rate: CGFloat, _ dt: CGFloat) -> CGFloat { v + (target - v) * (1 - exp(-rate * dt)) }
    static func hash(_ i: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(i)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return CGFloat(x % 10_000) / 10_000
    }
    static func time(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }
    static func ordinal(_ n: Int) -> String { n == 1 ? "1st" : n == 2 ? "2nd" : n == 3 ? "3rd" : "\(n)th" }
}

struct RaceRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

/// Text in RCol through Canvas (keeps call sites short).
extension Canvas {
    @discardableResult
    func rtext(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ col: RCol, _ weight: NSFont.Weight = .heavy,
               mono: Bool = false, align: NSTextAlignment = .left, maxWidth: CGFloat? = nil) -> CGFloat {
        text(s, x: x, y: y, size: size, color: col.ns, weight: weight, mono: mono, align: align, maxWidth: maxWidth)
    }
}
