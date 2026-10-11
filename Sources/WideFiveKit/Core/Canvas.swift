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
