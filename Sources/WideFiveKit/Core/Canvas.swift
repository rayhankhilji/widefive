import AppKit

/// Thin drawing layer over CGContext. Origin is bottom-left, units are points (Touch Bar is 30pt tall, 2x scale).
public final class Canvas {
    public let cg: CGContext
    public let size: CGSize
    public let theme: Theme
    public let time: Double

    public init(cg: CGContext, size: CGSize, theme: Theme, time: Double) {
        self.cg = cg
        self.size = size
        self.theme = theme
        self.time = time
    }

    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public var bounds: CGRect { CGRect(origin: .zero, size: size) }

    public func fill(_ rect: CGRect, _ color: NSColor) {
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
    }

    public func clear(_ color: NSColor = .black) { fill(bounds, color) }

    public func polygon(_ pts: [CGPoint], _ color: NSColor) {
        guard pts.count > 2 else { return }
        cg.setFillColor(color.cgColor)
        cg.beginPath()
        cg.move(to: pts[0])
        for p in pts.dropFirst() { cg.addLine(to: p) }
        cg.closePath()
        cg.fillPath()
    }

    public func roundRect(_ rect: CGRect, radius: CGFloat = 6, fill color: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
        let path = CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil)
        cg.addPath(path)
        cg.setFillColor(color.cgColor)
        cg.fillPath()
        if let stroke {
            cg.addPath(path)
            cg.setStrokeColor(stroke.cgColor)
            cg.setLineWidth(lineWidth)
            cg.strokePath()
        }
    }

    public func gradient(_ rect: CGRect, _ colors: [NSColor], horizontal: Bool = false, radius: CGFloat = 0) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: nil) else { return }
        cg.saveGState()
        if radius > 0 {
            cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        } else {
            cg.addRect(rect)
        }
        cg.clip()
        let start = horizontal ? CGPoint(x: rect.minX, y: rect.midY) : CGPoint(x: rect.midX, y: rect.maxY)
        let end = horizontal ? CGPoint(x: rect.maxX, y: rect.midY) : CGPoint(x: rect.midX, y: rect.minY)
        cg.drawLinearGradient(g, start: start, end: end, options: [])
        cg.restoreGState()
    }

    public func circle(center: CGPoint, radius: CGFloat, _ color: NSColor) {
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    public func line(from a: CGPoint, to b: CGPoint, _ color: NSColor, width: CGFloat = 1) {
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(width)
        cg.move(to: a)
        cg.addLine(to: b)
        cg.strokePath()
    }

    public static func font(_ size: CGFloat, _ weight: NSFont.Weight = .medium, mono: Bool = false) -> NSFont {
        mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }

    @discardableResult
    public func text(_ string: String, x: CGFloat, y: CGFloat? = nil, size: CGFloat = 12, color: NSColor = .white,
                     weight: NSFont.Weight = .medium, mono: Bool = false, align: NSTextAlignment = .left, maxWidth: CGFloat? = nil) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: Canvas.font(size, weight, mono: mono), .foregroundColor: color]
        var str = NSAttributedString(string: string, attributes: attrs)
        var w = str.size().width
        if let maxWidth, w > maxWidth, !string.isEmpty {
            var s = string
            while w > maxWidth, s.count > 1 {
                s.removeLast()
                str = NSAttributedString(string: s + "…", attributes: attrs)
                w = str.size().width
            }
        }
        let h = str.size().height
        let ox: CGFloat
        switch align {
        case .center: ox = x - w / 2
        case .right: ox = x - w
        default: ox = x
        }
        let oy = y ?? (height - h) / 2
        withGraphicsContext { str.draw(at: CGPoint(x: ox, y: oy)) }
        return w
    }

    public static func measure(_ string: String, size: CGFloat, weight: NSFont.Weight = .medium, mono: Bool = false) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font(size, weight, mono: mono)]).size().width
    }

    /// Draws an SF Symbol (macOS 11+) or falls back to treating `name` as literal text/emoji.
    public func symbol(_ name: String, in rect: CGRect, color: NSColor, pointSize: CGFloat = 14) {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold)) {
            let tinted = img.tinted(color)
            let s = tinted.size
            let r = CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height)
            withGraphicsContext { tinted.draw(in: r) }
        } else {
            text(name, x: rect.midX, y: nil, size: pointSize, color: color, align: .center)
        }
    }

    public func image(_ img: NSImage, in rect: CGRect, radius: CGFloat = 0) {
        withGraphicsContext {
            if radius > 0 {
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            }
            img.draw(in: rect)
        }
    }

    /// Pixel sprite: rows top→bottom, each char maps through palette; '.' or ' ' is transparent.
    public func sprite(_ sprite: Sprite, x: CGFloat, y: CGFloat, scale: CGFloat = 1, flipX: Bool = false, tint: NSColor? = nil) {
        let rows = sprite.rows
        let h = CGFloat(rows.count)
        for (ri, row) in rows.enumerated() {
            let chars = Array(row)
            let w = chars.count
            for (ci, ch) in chars.enumerated() {
                guard let color = tint ?? sprite.palette[ch] else { continue }
                let col = flipX ? (w - 1 - ci) : ci
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: x + CGFloat(col) * scale, y: y + (h - 1 - CGFloat(ri)) * scale, width: scale, height: scale))
            }
        }
    }

    public func withGraphicsContext(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    public func clip(_ rect: CGRect, _ body: () -> Void) {
        cg.saveGState()
        cg.clip(to: rect)
        body()
        cg.restoreGState()
    }
}


// MARK: - Design-system helpers

public enum ButtonStyle {
    /// Neutral surface.
    case plain
    /// Filled with the accent (or a given colour).
    case filled(NSColor?)
    /// Surface washed with a colour; content takes the colour.
    case tinted(NSColor)
    /// No resting background; only shows when pressed/selected.
    case ghost
}

public extension Canvas {
    /// Strip background (gradient when the theme has one).
    func background() {
        if let top = theme.backgroundTop { gradient(bounds, [top, theme.background]) } else { fill(bounds, theme.background) }
    }

    var cornerRadius: CGFloat { theme.radius }

    /// Draws `body` scaled around `center`.
    func scaled(_ s: CGFloat, around center: CGPoint, _ body: () -> Void) {
        guard abs(s - 1) > 0.0005 else { body(); return }
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.scaleBy(x: s, y: s)
        cg.translateBy(x: -center.x, y: -center.y)
        body()
        cg.restoreGState()
    }

    func translated(_ dx: CGFloat, _ dy: CGFloat = 0, _ body: () -> Void) {
        cg.saveGState(); cg.translateBy(x: dx, y: dy); body(); cg.restoreGState()
    }

    /// Group opacity: everything in `body` fades together.
    func faded(_ a: CGFloat, _ body: () -> Void) {
        if a >= 0.999 { body(); return }
        guard a > 0.001 else { return }
        cg.saveGState()
        cg.setAlpha(a)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    /// Soft bloom behind whatever `body` draws. Scaled by the theme's glow strength.
    func glowing(_ color: NSColor, blur: CGFloat = 8, strength: CGFloat = 1, _ body: () -> Void) {
        let a = theme.glow * strength
        guard a > 0.01 else { body(); return }
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: blur, color: color.withAlphaComponent(min(1, 0.85 * a)).cgColor)
        body()
        cg.restoreGState()
    }

    /// A themed card: soft vertical sheen, hairline border, top highlight.
    func panel(_ r: CGRect, fill: NSColor? = nil, radius: CGFloat? = nil, stroke: NSColor? = nil, sheen: Bool = true) {
        let rad = min(radius ?? theme.radius, r.height / 2, r.width / 2)
        let base = fill ?? theme.surface
        if sheen, base.alphaComponent > 0.05 {
            let top = theme.isLight ? base.mix(.white, 0.5) : base.mix(.white, 0.07)
            let bottom = theme.isLight ? base.mix(.black, 0.02) : base.mix(.black, 0.12)
            gradient(r, [top, bottom], radius: rad)
        } else {
            roundRect(r, radius: rad, fill: base)
        }
        let path = CGPath(roundedRect: r.insetBy(dx: 0.25, dy: 0.25), cornerWidth: max(0, rad - 0.25), cornerHeight: max(0, rad - 0.25), transform: nil)
        cg.addPath(path)
        cg.setStrokeColor((stroke ?? theme.stroke).cgColor)
        cg.setLineWidth(0.5)
        cg.strokePath()
        if sheen, !theme.isLight, r.width > rad * 2 + 2 {
            self.fill(CGRect(x: r.minX + rad, y: r.maxY - 1, width: r.width - rad * 2, height: 0.5), theme.highlight)
        }
    }

    /// Standard button chrome with press animation. `body` draws the content (already scaled) with the right
    /// foreground colour. `pressed` is 0…1 from `Presses`, `selected` lights it up.
    func button(_ r: CGRect, style: ButtonStyle = .plain, pressed: CGFloat = 0, selected: Bool = false,
                radius: CGFloat? = nil, _ body: (NSColor) -> Void = { _ in }) {
        let p = max(0, min(1, pressed))
        scaled(1 - 0.06 * p, around: CGPoint(x: r.midX, y: r.midY)) {
            var fg = theme.text
            switch style {
            case .plain:
                let f = selected ? theme.accent : theme.surface.mix(theme.surfaceHi, p)
                if selected { glowing(theme.accent, blur: 7, strength: 0.7) { panel(r, fill: f, radius: radius) } } else { panel(r, fill: f, radius: radius) }
                fg = selected ? theme.onAccent : theme.text
            case .filled(let c):
                let col = c ?? theme.accent
                glowing(col, blur: 6 + 6 * p, strength: 0.55 + 0.45 * p) { panel(r, fill: col.mix(theme.isLight ? .black : .white, 0.18 * p), radius: radius) }
                fg = theme.on(col)
            case .tinted(let c):
                let wash = theme.surface.mix(c, (theme.isLight ? 0.16 : 0.22) + 0.25 * p + (selected ? 0.4 : 0))
                panel(r, fill: wash, radius: radius, stroke: c.withAlphaComponent(theme.isLight ? 0.35 : 0.28))
                fg = selected ? theme.on(wash) : (theme.isLight ? c.mix(.black, 0.15) : c.mix(.white, 0.15))
            case .ghost:
                if p > 0.01 || selected {
                    panel(r, fill: (selected ? theme.surfaceHi : theme.surface).withAlphaComponent(max(selected ? 1 : 0, p)), radius: radius)
                }
            }
            if p > 0.01, theme.glow > 0 {
                glowing(theme.accent, blur: 10, strength: p * 0.8) {
                    roundRect(r, radius: radius ?? theme.radius, fill: .clear, stroke: theme.accent.withAlphaComponent(0.55 * p), lineWidth: 1)
                }
            }
            body(fg)
        }
    }

    /// Fades content into the background at a scroll edge.
    func edgeFade(x: CGFloat, width: CGFloat, leftEdge: Bool) {
        let bg = theme.background
        let r = CGRect(x: leftEdge ? x : x - width, y: 0, width: width, height: height)
        let cols = leftEdge ? [bg, bg.withAlphaComponent(0)] : [bg.withAlphaComponent(0), bg]
        gradient(r, cols, horizontal: true)
    }

    /// Draws `body` with its left/right edges alpha-faded (works over any background).
    func fadeEdges(_ r: CGRect, left: CGFloat, right: CGFloat, _ body: () -> Void) {
        guard left > 0.5 || right > 0.5 else { body(); return }
        cg.saveGState()
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        cg.setBlendMode(.destinationOut)
        let solid = NSColor.black, clear = NSColor.black.withAlphaComponent(0)
        if left > 0.5 { gradient(CGRect(x: r.minX, y: r.minY, width: left, height: r.height), [solid, clear], horizontal: true) }
        if right > 0.5 { gradient(CGRect(x: r.maxX - right, y: r.minY, width: right, height: r.height), [clear, solid], horizontal: true) }
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    /// Progress ring (fraction 0…1, clockwise from 12 o'clock).
    func ring(center: CGPoint, radius: CGFloat, width: CGFloat, fraction: CGFloat, color: NSColor, track: NSColor? = nil) {
        cg.saveGState()
        cg.setLineCap(.round)
        cg.setLineWidth(width)
        cg.setStrokeColor((track ?? theme.dim.withAlphaComponent(0.25)).cgColor)
        cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        cg.strokePath()
        if fraction > 0.001 {
            cg.setStrokeColor(color.cgColor)
            cg.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - min(1, fraction) * .pi * 2, clockwise: true)
            cg.strokePath()
        }
        cg.restoreGState()
    }

    /// Thin progress/level bar with a gradient fill.
    func meter(_ r: CGRect, value: CGFloat, colors: [NSColor]? = nil, track: NSColor? = nil) {
        let rad = r.height / 2
        roundRect(r, radius: rad, fill: track ?? theme.dim.withAlphaComponent(theme.isLight ? 0.22 : 0.25))
        let v = max(0, min(1, value))
        guard v > 0.001 else { return }
        let fillR = CGRect(x: r.minX, y: r.minY, width: max(r.height, r.width * v), height: r.height)
        gradient(fillR, colors ?? [theme.accent, theme.accent2], horizontal: true, radius: rad)
    }

    /// Small uppercase label.
    @discardableResult
    func caption(_ s: String, x: CGFloat, y: CGFloat? = nil, color: NSColor? = nil, align: NSTextAlignment = .left, maxWidth: CGFloat? = nil) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: Canvas.font(Metrics.Font.caption, .bold), .foregroundColor: color ?? theme.dim, .kern: 0.6]
        let str = NSAttributedString(string: s.uppercased(), attributes: attrs)
        let size = str.size()
        let ox = align == .center ? x - size.width / 2 : (align == .right ? x - size.width : x)
        let oy = y ?? (height - size.height) / 2
        clip(CGRect(x: ox, y: 0, width: maxWidth ?? size.width + 1, height: height)) { withGraphicsContext { str.draw(at: CGPoint(x: ox, y: oy)) } }
        return size.width
    }
}

public struct Sprite {
    public let rows: [String]
    public let palette: [Character: NSColor]
    public init(_ rows: [String], _ palette: [Character: NSColor]) {
        self.rows = rows
        self.palette = palette
    }
    public var width: Int { rows.map { $0.count }.max() ?? 0 }
    public var height: Int { rows.count }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        draw(in: CGRect(origin: .zero, size: size))
        color.set()
        CGRect(origin: .zero, size: size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

public extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 3 {
            let r = CGFloat((v >> 8) & 0xF) / 15, g = CGFloat((v >> 4) & 0xF) / 15, b = CGFloat(v & 0xF) / 15
            self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
        } else {
            self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
        }
    }

    static func hsb(_ h: CGFloat, _ s: CGFloat = 1, _ b: CGFloat = 1, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedHue: h.truncatingRemainder(dividingBy: 1).magnitude, saturation: s, brightness: b, alpha: a)
    }
}
