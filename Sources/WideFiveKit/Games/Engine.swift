import AppKit

/// Tiny tile-based platformer engine sized for a 30pt-tall strip: 5pt tiles × 6 rows.
public enum Tile: UInt8 {
    case empty, ground, brick, question, used, block, pipe, spike, platform

    public var isSolid: Bool {
        switch self {
        case .ground, .brick, .question, .used, .block, .pipe, .platform: return true
        default: return false
        }
    }
}

public struct Body {
    public var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    public var vx: CGFloat = 0, vy: CGFloat = 0
    public var onGround = false
    public var hitCeiling = false
    public var hitWall = false
    public init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    public var midX: CGFloat { x + w / 2 }
}

public final class TileWorld {
    public static let T: CGFloat = 5
    public static let rows = 6
    public var cols: [[Tile]] = []
    /// World column index of cols[0] (endless games drop old columns).
    public var origin = 0
    public var leftWall = true

    public init() {}

    public var endColumn: Int { origin + cols.count }
    public var width: CGFloat { CGFloat(endColumn) * Self.T }

    public func get(_ c: Int, _ r: Int) -> Tile {
        if r < 0 || r >= Self.rows { return .empty }
        if c < origin { return leftWall ? .block : .empty }
        let i = c - origin
        return i < cols.count ? cols[i][r] : .empty
    }

    public func set(_ c: Int, _ r: Int, _ t: Tile) {
        let i = c - origin
        guard i >= 0, i < cols.count, r >= 0, r < Self.rows else { return }
        cols[i][r] = t
    }

    public func append(_ column: [Tile]) { cols.append(column) }
    public func emptyColumn() -> [Tile] { Array(repeating: .empty, count: Self.rows) }

    public func dropBefore(_ c: Int) {
        let n = min(cols.count, c - origin)
        if n > 0 { cols.removeFirst(n); origin += n }
    }

    /// Axis-separated move with tile collision. `gravityDown == false` treats the ceiling as the floor (Flip).
    public func move(_ b: inout Body, dt: CGFloat, gravityDown: Bool = true, onBump: ((Int, Int) -> Void)? = nil) {
        let T = Self.T
        b.hitWall = false
        b.x += b.vx * dt
        let r0 = Int(floor((b.y + 0.01) / T)), r1 = Int(floor((b.y + b.h - 0.01) / T))
        if b.vx > 0 {
            let c = Int(floor((b.x + b.w) / T))
            if (r0...r1).contains(where: { get(c, $0).isSolid }) { b.x = CGFloat(c) * T - b.w; b.vx = 0; b.hitWall = true }
        } else if b.vx < 0 {
            let c = Int(floor(b.x / T))
            if (r0...r1).contains(where: { get(c, $0).isSolid }) { b.x = CGFloat(c + 1) * T; b.vx = 0; b.hitWall = true }
        }
        b.onGround = false
        b.hitCeiling = false
        b.y += b.vy * dt
        let c0 = Int(floor((b.x + 0.01) / T)), c1 = Int(floor((b.x + b.w - 0.01) / T))
        if b.vy < 0 {
            let r = Int(floor(b.y / T))
            if let hit = (c0...c1).first(where: { get($0, r).isSolid }) {
                b.y = CGFloat(r + 1) * T; b.vy = 0
                if gravityDown { b.onGround = true } else { b.hitCeiling = true; onBump?(hit, r) }
            }
        } else if b.vy > 0 {
            let r = Int(floor((b.y + b.h) / T))
            let hits = (c0...c1).filter { get($0, r).isSolid }
            if !hits.isEmpty {
                b.y = CGFloat(r) * T - b.h; b.vy = 0
                if gravityDown {
                    b.hitCeiling = true
                    // Bump the tile closest to the body's center (Mario-style).
                    let best = hits.min { abs((CGFloat($0) + 0.5) * T - b.midX) < abs((CGFloat($1) + 0.5) * T - b.midX) }!
                    onBump?(best, r)
                } else { b.onGround = true }
            }
        }
    }

    public func touches(_ b: Body, _ tile: Tile, inset: CGFloat = 1) -> Bool {
        let T = Self.T
        let c0 = Int(floor((b.x + inset) / T)), c1 = Int(floor((b.x + b.w - inset) / T))
        let r0 = Int(floor((b.y + inset) / T)), r1 = Int(floor((b.y + b.h - inset) / T))
        guard c0 <= c1, r0 <= r1 else { return false }
        for c in c0...c1 { for r in r0...r1 where get(c, r) == tile { return true } }
        return false
    }

    public func solidBelow(_ x: CGFloat, _ y: CGFloat) -> Bool { get(Int(floor(x / Self.T)), Int(floor((y - 1) / Self.T))).isSolid }
}

// MARK: - Particles

public enum ParticleKind { case square, dot, glow, streak, ring, sparkle, shard }

public struct Particle {
    public var x, y, vx, vy: CGFloat
    public var life: CGFloat
    public var maxLife: CGFloat
    public var color: NSColor
    public var size: CGFloat
    public var gravity: CGFloat
    public var kind: ParticleKind = .square
    public var drag: CGFloat = 0
    public var spin: CGFloat = 0
    public var angle: CGFloat = 0
}

/// Lightweight particle system shared by every game: squares, glowing dots, velocity streaks, shock rings, sparkles.
public final class Particles {
    public var items: [Particle] = []
    public init() {}

    public func burst(x: CGFloat, y: CGFloat, count: Int, colors: [NSColor], speed: CGFloat = 60, life: CGFloat = 0.6, size: CGFloat = 1.5,
                      gravity: CGFloat = -200, kind: ParticleKind = .square, drag: CGFloat = 0, direction: CGFloat? = nil,
                      spread: CGFloat = .pi * 2, upBias: CGFloat = 0.4) {
        guard !colors.isEmpty else { return }
        for _ in 0..<count {
            let a: CGFloat = direction.map { $0 + CGFloat.random(in: -spread / 2...spread / 2) } ?? CGFloat.random(in: 0...(2 * .pi))
            let s = CGFloat.random(in: speed * 0.3...max(speed * 0.3 + 0.01, speed))
            let l = life * CGFloat.random(in: 0.7...1.15)
            items.append(Particle(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s + (direction == nil ? speed * upBias : 0), life: l, maxLife: l,
                                  color: colors.randomElement()!, size: size * CGFloat.random(in: 0.7...1.25), gravity: gravity,
                                  kind: kind, drag: drag, spin: CGFloat.random(in: -14...14), angle: CGFloat.random(in: 0...6.28)))
        }
    }

    /// Expanding shock ring.
    public func ring(x: CGFloat, y: CGFloat, color: NSColor, radius: CGFloat = 10, life: CGFloat = 0.35) {
        items.append(Particle(x: x, y: y, vx: 0, vy: 0, life: life, maxLife: life, color: color, size: radius, gravity: 0, kind: .ring))
    }

    /// Soft light flash (muzzle flashes, explosions).
    public func flash(x: CGFloat, y: CGFloat, color: NSColor, radius: CGFloat = 8, life: CGFloat = 0.12) {
        items.append(Particle(x: x, y: y, vx: 0, vy: 0, life: life, maxLife: life, color: color, size: radius, gravity: 0, kind: .glow))
    }

    public func update(_ dt: CGFloat) {
        for i in items.indices {
            items[i].x += items[i].vx * dt
            items[i].y += items[i].vy * dt
            items[i].vy += items[i].gravity * dt
            if items[i].drag > 0 {
                let k = max(0, 1 - items[i].drag * dt)
                items[i].vx *= k; items[i].vy *= k
            }
            items[i].angle += items[i].spin * dt
            items[i].life -= dt
        }
        items.removeAll { $0.life <= 0 }
    }

    public func draw(_ c: Canvas, camX: CGFloat, camY: CGFloat = 0) {
        for p in items {
            let a = max(0, min(1, p.life / p.maxLife))
            let x = p.x - camX, y = p.y - camY
            guard x > -40, x < c.width + 40 else { continue }
            switch p.kind {
            case .square:
                let s = p.size * (0.35 + 0.65 * a)
                c.fill(CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s), p.color.withAlphaComponent(a))
            case .dot:
                c.circle(center: CGPoint(x: x, y: y), radius: p.size * (0.3 + 0.7 * a) / 2, p.color.withAlphaComponent(min(1, a * 1.4)))
            case .glow:
                Glow.radial(c, CGPoint(x: x, y: y), p.size * (0.6 + 0.4 * (1 - a)), p.color, alpha: a)
            case .streak:
                let len = max(1, hypot(p.vx, p.vy) * 0.035)
                let ang = atan2(p.vy, p.vx)
                c.line(from: CGPoint(x: x, y: y), to: CGPoint(x: x - cos(ang) * len, y: y - sin(ang) * len),
                       p.color.withAlphaComponent(a), width: p.size * (0.4 + 0.6 * a))
            case .ring:
                let r = p.size * (0.25 + 0.75 * CGFloat(Ease.outCubic(Double(1 - a))))
                c.cg.setStrokeColor(p.color.withAlphaComponent(a * 0.9).cgColor)
                c.cg.setLineWidth(max(0.3, 1.6 * a))
                c.cg.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            case .sparkle:
                Icons.sparkle(c, CGPoint(x: x, y: y), p.size * (0.4 + 0.6 * a), p.color.withAlphaComponent(a), rotation: p.angle * 0.2)
            case .shard:
                let s = p.size * (0.5 + 0.5 * a)
                c.cg.saveGState()
                c.cg.translateBy(x: x, y: y); c.cg.rotate(by: p.angle)
                c.fill(CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2), p.color.withAlphaComponent(min(1, a * 1.5)))
                c.cg.restoreGState()
            }
        }
    }
}

// MARK: - Juice: easing, screen shake, glow, icons

/// Trauma-based screen shake: add trauma on impacts, it decays smoothly; offset grows with trauma².
public final class Shake {
    public var trauma: CGFloat = 0
    public var maxOffset: CGFloat = 3.2
    private var clock: Double = 0
    public init(maxOffset: CGFloat = 3.2) { self.maxOffset = maxOffset }
    public func add(_ amount: CGFloat) { trauma = min(1, trauma + amount) }
    public func update(_ dt: CGFloat) { trauma = max(0, trauma - dt * 1.8); clock += Double(dt) }
    public func reset() { trauma = 0 }
    public var offset: CGPoint {
        let s = trauma * trauma * maxOffset
        let t = clock * 38
        return CGPoint(x: s * CGFloat(sin(t * 1.13) * 0.6 + sin(t * 2.71) * 0.4),
                       y: s * 0.55 * CGFloat(sin(t * 1.71 + 2) * 0.6 + sin(t * 3.17) * 0.4))
    }
    public func apply(_ c: Canvas) { let o = offset; c.cg.translateBy(x: o.x, y: o.y) }
}

public enum Glow {
    /// Soft radial light: `color` at the center fading to transparent at `radius`.
    public static func radial(_ c: Canvas, _ center: CGPoint, _ radius: CGFloat, _ color: NSColor, alpha: CGFloat = 1) {
        guard radius > 0.1, alpha > 0.01 else { return }
        let col = color.usingColorSpace(.deviceRGB) ?? color
        let colors = [col.withAlphaComponent(alpha * col.alphaComponent).cgColor, col.withAlphaComponent(alpha * 0.35 * col.alphaComponent).cgColor,
                      col.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return }
        c.cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// Rounded rect drawn with a soft halo.
    public static func capsule(_ c: Canvas, _ r: CGRect, _ color: NSColor, halo: CGFloat = 2.5, intensity: CGFloat = 0.35) {
        for k in stride(from: halo, to: 0, by: -max(0.5, halo / 3)) {
            c.roundRect(r.insetBy(dx: -k, dy: -k), radius: r.height / 2 + k, fill: color.withAlphaComponent(intensity * (1 - k / (halo + 0.5)) * 0.5))
        }
        c.roundRect(r, radius: r.height / 2, fill: color)
    }

    /// Full-strip vignette to focus the eye on the middle of the action.
    public static func vignette(_ c: Canvas, strength: CGFloat = 0.45) {
        c.gradient(CGRect(x: 0, y: 0, width: 90, height: c.height), [NSColor(white: 0, alpha: strength), NSColor(white: 0, alpha: 0)], horizontal: true)
        c.gradient(CGRect(x: c.width - 90, y: 0, width: 90, height: c.height), [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: strength)], horizontal: true)
        c.gradient(CGRect(x: 0, y: c.height - 5, width: c.width, height: 5), [NSColor(white: 0, alpha: strength * 0.6), NSColor(white: 0, alpha: 0)])
    }
}

/// Small vector icons used by HUDs and pickups.
public enum Icons {
    public static func heart(_ c: Canvas, _ center: CGPoint, _ s: CGFloat, _ color: NSColor) {
        let p = CGMutablePath()
        let x = center.x, y = center.y
        p.move(to: CGPoint(x: x, y: y - s * 0.55))
        p.addCurve(to: CGPoint(x: x - s * 0.55, y: y + s * 0.1), control1: CGPoint(x: x - s * 0.15, y: y - s * 0.3), control2: CGPoint(x: x - s * 0.55, y: y - s * 0.2))
        p.addArc(center: CGPoint(x: x - s * 0.27, y: y + s * 0.18), radius: s * 0.29, startAngle: .pi * 1.05, endAngle: 0, clockwise: true)
        p.addArc(center: CGPoint(x: x + s * 0.27, y: y + s * 0.18), radius: s * 0.29, startAngle: .pi, endAngle: -0.05 * .pi, clockwise: true)
        p.addCurve(to: CGPoint(x: x, y: y - s * 0.55), control1: CGPoint(x: x + s * 0.55, y: y - s * 0.2), control2: CGPoint(x: x + s * 0.15, y: y - s * 0.3))
        c.cg.addPath(p); c.cg.setFillColor(color.cgColor); c.cg.fillPath()
    }

    public static func star(_ c: Canvas, _ center: CGPoint, _ r: CGFloat, _ color: NSColor, points: Int = 5, inner: CGFloat = 0.45, rotation: CGFloat = 0) {
        var pts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let a = rotation + CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let rr = i % 2 == 0 ? r : r * inner
            pts.append(CGPoint(x: center.x + cos(a) * rr, y: center.y + sin(a) * rr))
        }
        c.polygon(pts, color)
    }

    public static func sparkle(_ c: Canvas, _ center: CGPoint, _ r: CGFloat, _ color: NSColor, rotation: CGFloat = 0) {
        star(c, center, r, color, points: 4, inner: 0.22, rotation: rotation)
    }

    public static func coin(_ c: Canvas, _ center: CGPoint, _ r: CGFloat, spin: Double = 0) {
        let w = r * CGFloat(abs(cos(spin))) + 0.35
        c.cg.setFillColor(NSColor(hex: "#b8860b").cgColor)
        c.cg.fillEllipse(in: CGRect(x: center.x - w, y: center.y - r, width: w * 2, height: r * 2))
        c.cg.setFillColor(NSColor(hex: "#ffd23f").cgColor)
        c.cg.fillEllipse(in: CGRect(x: center.x - w * 0.82, y: center.y - r * 0.86, width: w * 1.64, height: r * 1.72))
        if w > r * 0.4 {
            c.fill(CGRect(x: center.x - w * 0.18, y: center.y - r * 0.45, width: w * 0.36, height: r * 0.9), NSColor(hex: "#e0a800"))
        }
        c.cg.setFillColor(NSColor(white: 1, alpha: 0.7).cgColor)
        c.cg.fillEllipse(in: CGRect(x: center.x - w * 0.55, y: center.y + r * 0.2, width: w * 0.4, height: r * 0.4))
    }

    public static func gem(_ c: Canvas, _ center: CGPoint, _ r: CGFloat, _ color: NSColor) {
        let x = center.x, y = center.y
        c.polygon([CGPoint(x: x, y: y + r), CGPoint(x: x + r * 0.8, y: y + r * 0.2), CGPoint(x: x, y: y - r), CGPoint(x: x - r * 0.8, y: y + r * 0.2)], color)
        c.polygon([CGPoint(x: x, y: y + r), CGPoint(x: x + r * 0.8, y: y + r * 0.2), CGPoint(x: x, y: y + r * 0.1), CGPoint(x: x - r * 0.8, y: y + r * 0.2)],
                  NSColor(white: 1, alpha: 0.45))
        c.polygon([CGPoint(x: x, y: y - r), CGPoint(x: x + r * 0.8, y: y + r * 0.2), CGPoint(x: x, y: y + r * 0.1)], NSColor(white: 0, alpha: 0.22))
    }

    /// Simple vector glyphs for touch buttons.
    public static func glyph(_ c: Canvas, _ name: String, in r: CGRect, _ color: NSColor) {
        let s = min(r.width, r.height) * 0.34
        let x = r.midX, y = r.midY
        switch name {
        case "L": c.polygon([CGPoint(x: x - s, y: y), CGPoint(x: x + s * 0.7, y: y + s), CGPoint(x: x + s * 0.7, y: y - s)], color)
        case "R": c.polygon([CGPoint(x: x + s, y: y), CGPoint(x: x - s * 0.7, y: y + s), CGPoint(x: x - s * 0.7, y: y - s)], color)
        case "U": c.polygon([CGPoint(x: x, y: y + s), CGPoint(x: x - s, y: y - s * 0.7), CGPoint(x: x + s, y: y - s * 0.7)], color)
        case "D": c.polygon([CGPoint(x: x, y: y - s), CGPoint(x: x - s, y: y + s * 0.7), CGPoint(x: x + s, y: y + s * 0.7)], color)
        case "F": c.circle(center: CGPoint(x: x, y: y), radius: s * 0.75, color)
        case "S": star(c, CGPoint(x: x, y: y), s * 1.05, color)
        default: c.text(name, x: x, y: y - 5.5, size: 9, color: color, weight: .black, align: .center)
        }
    }
}

// MARK: - Touch controls shared by the platformers

/// Left: ◀ ▶ pad (slide between them). Right: B (run) + A (jump). Multi-touch.
public final class PadControls {
    public var left = false, right = false, run = false, jump = false
    public var jumpPressed = false   // edge-triggered, cleared by the game
    private var owners: [Int: String] = [:]
    public var padX: CGFloat = StripController.gameChromeWidth + 3
    public let padW: CGFloat = 92
    public let btnW: CGFloat = 40
    public var width: CGFloat = 1085
    /// Labels for the two right-hand buttons (B, A).
    public var labels = ("B", "A")
    private var pressT: [String: Double] = [:]

    public init() {}

    /// On-bar buttons only exist while the keyboard isn't locked to the game.
    public var visible: Bool { !KeyCapture.shared.active }

    private func zone(_ x: CGFloat) -> String? {
        guard visible else { return nil }
        if x >= padX, x < padX + padW { return x < padX + padW / 2 ? "L" : "R" }
        if x > width - btnW - 3 { return "A" }
        if x > width - btnW * 2 - 7 { return "B" }
        return nil
    }

    private func recompute() {
        let z = Set(owners.values)
        left = z.contains("L"); right = z.contains("R"); run = z.contains("B")
        let j = z.contains("A")
        if j && !jump { jumpPressed = true }
        jump = j
    }

    @discardableResult public func began(_ t: StripTouch) -> Bool {
        guard let z = zone(t.x) else { return false }
        owners[t.id] = z; recompute(); return true
    }
    public func moved(_ t: StripTouch) {
        guard let cur = owners[t.id] else { return }
        if cur == "L" || cur == "R", let z = zone(t.x), z == "L" || z == "R" { owners[t.id] = z; recompute() }
    }
    public func ended(_ t: StripTouch) { owners[t.id] = nil; recompute() }
    public func reset() { owners.removeAll(); left = false; right = false; run = false; jump = false; jumpPressed = false }

    public func key(_ k: GameKey, down: Bool) {
        switch k {
        case .left: left = down
        case .right: right = down
        case .run: run = down
        case .jump, .up:
            if down && !jump { jumpPressed = true }
            jump = down
        default: break
        }
    }

    public func draw(_ c: Canvas) {
        guard visible else { return }
        let lr = CGRect(x: padX, y: 3, width: padW / 2 - 1.5, height: 24)
        let rr = CGRect(x: padX + padW / 2 + 1.5, y: 3, width: padW / 2 - 1.5, height: 24)
        TouchButton.draw(c, lr, glyph: "L", on: left, tint: NSColor(white: 0.85, alpha: 1))
        TouchButton.draw(c, rr, glyph: "R", on: right, tint: NSColor(white: 0.85, alpha: 1))
        TouchButton.draw(c, CGRect(x: width - btnW * 2 - 6, y: 3, width: btnW, height: 24), glyph: labels.0, on: run, tint: NSColor(hex: "#4f7bff"))
        TouchButton.draw(c, CGRect(x: width - btnW - 3, y: 3, width: btnW, height: 24), glyph: labels.1, on: jump, tint: NSColor(hex: "#ff4d5e"))
    }
}

/// Glassy, low-key touch button used by every game's on-bar controls.
public enum TouchButton {
    public static func draw(_ c: Canvas, _ r: CGRect, glyph: String, on: Bool, tint: NSColor) {
        let rr = on ? r.insetBy(dx: 0.8, dy: 0.8) : r
        if on { Glow.radial(c, CGPoint(x: rr.midX, y: rr.midY), rr.width * 0.75, tint, alpha: 0.35) }
        c.roundRect(rr, radius: rr.height / 2, fill: on ? tint.withAlphaComponent(0.55) : NSColor(white: 0.02, alpha: 0.38),
                    stroke: tint.withAlphaComponent(on ? 0.95 : 0.4), lineWidth: 0.7)
        c.roundRect(CGRect(x: rr.minX + 3, y: rr.maxY - rr.height * 0.42, width: rr.width - 6, height: rr.height * 0.32), radius: rr.height * 0.16,
                    fill: NSColor(white: 1, alpha: on ? 0.18 : 0.07))
        Icons.glyph(c, glyph, in: rr, on ? .white : tint.withAlphaComponent(0.85))
    }
}

/// Persistent high scores.
public enum HighScores {
    public static func get(_ game: String) -> Int { UserDefaults.standard.integer(forKey: "widefive.hi.\(game)") }
    @discardableResult public static func submit(_ game: String, _ score: Int) -> Bool {
        guard score > get(game) else { return false }
        UserDefaults.standard.set(score, forKey: "widefive.hi.\(game)")
        return true
    }
}
