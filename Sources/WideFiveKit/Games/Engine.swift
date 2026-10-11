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

public struct Particle {
    public var x, y, vx, vy: CGFloat
    public var life: CGFloat
    public var maxLife: CGFloat
    public var color: NSColor
    public var size: CGFloat
    public var gravity: CGFloat
}

public final class Particles {
    public var items: [Particle] = []
    public init() {}
    public func burst(x: CGFloat, y: CGFloat, count: Int, colors: [NSColor], speed: CGFloat = 60, life: CGFloat = 0.6, size: CGFloat = 1.5, gravity: CGFloat = -200) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2 * .pi)), s = CGFloat.random(in: speed * 0.3...speed)
            items.append(Particle(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s + speed * 0.4, life: life, maxLife: life,
                                  color: colors.randomElement()!, size: size, gravity: gravity))
        }
    }
    public func update(_ dt: CGFloat) {
        for i in items.indices {
            items[i].x += items[i].vx * dt
            items[i].y += items[i].vy * dt
            items[i].vy += items[i].gravity * dt
            items[i].life -= dt
        }
        items.removeAll { $0.life <= 0 }
    }
    public func draw(_ c: Canvas, camX: CGFloat) {
        for p in items {
            c.fill(CGRect(x: p.x - camX, y: p.y, width: p.size, height: p.size), p.color.withAlphaComponent(max(0, p.life / p.maxLife)))
        }
    }
}

// MARK: - Touch controls shared by the platformers

/// Left: ◀ ▶ pad (slide between them). Right: B (run) + A (jump). Multi-touch.
public final class PadControls {
    public var left = false, right = false, run = false, jump = false
    public var jumpPressed = false   // edge-triggered, cleared by the game
    private var owners: [Int: String] = [:]
    public var padX: CGFloat = StripController.exitWidth + 2
    public let padW: CGFloat = 130
    public let btnW: CGFloat = 64
    public var width: CGFloat = 1085

    public init() {}

    private func zone(_ x: CGFloat) -> String? {
        if x >= padX, x < padX + padW { return x < padX + padW / 2 ? "L" : "R" }
        if x > width - btnW { return "A" }
        if x > width - btnW * 2 - 4 { return "B" }
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
        let alpha: CGFloat = 0.28
        func btn(_ r: CGRect, _ label: String, _ on: Bool, _ color: NSColor) {
            c.roundRect(r, radius: 7, fill: color.withAlphaComponent(on ? 0.75 : alpha), stroke: NSColor(white: 1, alpha: 0.35), lineWidth: 0.75)
            c.text(label, x: r.midX, size: 12, color: NSColor(white: 1, alpha: 0.9), weight: .heavy, align: .center)
        }
        btn(CGRect(x: padX, y: 1, width: padW / 2 - 2, height: 28), "◀", left, .black)
        btn(CGRect(x: padX + padW / 2, y: 1, width: padW / 2 - 2, height: 28), "▶", right, .black)
        btn(CGRect(x: width - btnW * 2 - 4, y: 1, width: btnW, height: 28), "B", run, NSColor(hex: "#2038ec"))
        btn(CGRect(x: width - btnW, y: 1, width: btnW, height: 28), "A", jump, NSColor(hex: "#e52521"))
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
