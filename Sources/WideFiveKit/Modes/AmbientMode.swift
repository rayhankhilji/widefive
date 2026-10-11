import AppKit

/// Eye candy for the strip. Tap to cycle scenes; in Life, touches seed gliders.
public final class AmbientMode: StripMode {
    public let id = "ambient"
    public let title = "Ambient"
    public let icon = "sparkles"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }

    let scenes = ["nyan", "matrix", "starfield", "life", "fire", "aurora"]
    var scene = 0
    private var w = 1085, h = 30

    // Life / fire grids (2pt cells)
    private let cell: CGFloat = 2
    private var gw = 0, gh = 15
    private var life: [UInt8] = []
    private var fire: [UInt8] = []
    private var lifeAcc = 0.0
    private var stars: [(x: CGFloat, y: CGFloat, z: CGFloat)] = []
    private var drops: [(x: CGFloat, y: CGFloat, speed: CGFloat, len: Int)] = []
    private var catX: CGFloat = -60
    private var t = 0.0

    public init() {}

    public func activate(_ ctx: ModeContext) { reset(width: ctx.size.width) }

    private func reset(width: CGFloat) {
        w = Int(width)
        gw = Int(width / cell)
        life = (0..<(gw * gh)).map { _ in UInt8.random(in: 0...3) == 0 ? 1 : 0 }
        fire = Array(repeating: 0, count: gw * gh)
        stars = (0..<220).map { _ in (CGFloat.random(in: -1...1), CGFloat.random(in: -1...1), CGFloat.random(in: 0.05...1)) }
        drops = (0..<(w / 7)).map { i in (CGFloat(i * 7), CGFloat.random(in: 0...60), CGFloat.random(in: 20...60), Int.random(in: 3...8)) }
    }

    public func update(dt: Double) {
        t += dt
        switch scenes[scene] {
        case "life":
            lifeAcc += dt
            if lifeAcc > 1.0 / 14 { lifeAcc = 0; stepLife() }
        case "fire": stepFire()
        case "starfield":
            for i in stars.indices {
                stars[i].z -= CGFloat(dt) * 0.35
                if stars[i].z <= 0.02 { stars[i] = (CGFloat.random(in: -1...1), CGFloat.random(in: -1...1), 1) }
            }
        case "matrix":
            for i in drops.indices {
                drops[i].y -= drops[i].speed * CGFloat(dt)
                if drops[i].y < -CGFloat(drops[i].len * 4) { drops[i].y = CGFloat.random(in: 32...60); drops[i].speed = CGFloat.random(in: 20...60) }
            }
        case "nyan":
            catX += CGFloat(dt) * 90
            if catX > CGFloat(w) + 40 { catX = -60 }
        default: break
        }
    }

    private func stepLife() {
        var next = life
        for y in 0..<gh {
            for x in 0..<gw {
                var n = 0
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let xx = (x + dx + gw) % gw, yy = (y + dy + gh) % gh
                    n += Int(life[yy * gw + xx] & 1)
                } }
                let alive = life[y * gw + x] & 1 == 1
                next[y * gw + x] = (alive && (n == 2 || n == 3)) || (!alive && n == 3) ? 1 : 0
            }
        }
        life = next
    }

    private func stepFire() {
        for x in 0..<gw { fire[x] = UInt8.random(in: 0...3) == 0 ? 0 : 36 }
        for y in 1..<gh {
            for x in 0..<gw {
                let src = (y - 1) * gw + x
                let decay = Int.random(in: 0...2)
                let dx = min(gw - 1, max(0, x - decay + 1))
                fire[y * gw + dx] = UInt8(max(0, Int(fire[src]) - (decay & 1) * 3))
            }
        }
    }

    public func draw(_ c: Canvas) {
        if Int(c.width) != w { reset(width: c.width) }
        switch scenes[scene] {
        case "nyan": drawNyan(c)
        case "matrix":
            for d in drops {
                for k in 0..<d.len {
                    let a = 1 - CGFloat(k) / CGFloat(d.len)
                    let col = k == 0 ? NSColor(hex: "#d8ffd8") : NSColor(hex: "#00ff6a").withAlphaComponent(a)
                    let glyphOn = (Int(d.x) * 7 + k * 13 + Int(t * 8)) % 5 != 0
                    if glyphOn { c.fill(CGRect(x: d.x, y: d.y + CGFloat(k) * 4, width: 3, height: 3), col) }
                }
            }
        case "starfield":
            let cx = c.width / 2, cy = c.height / 2
            for s in stars {
                let x = cx + s.x / s.z * cx, y = cy + s.y / s.z * cy * 0.6
                let size = max(0.6, (1 - s.z) * 2.6)
                c.fill(CGRect(x: x, y: y, width: size * 2.5, height: size * 0.6), NSColor(white: 1, alpha: 1 - s.z))
            }
        case "life":
            for y in 0..<gh { for x in 0..<gw where life[y * gw + x] == 1 {
                c.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell - 0.3, height: cell - 0.3), .hsb(CGFloat(x) / CGFloat(gw) + CGFloat(t * 0.1), 0.8, 1))
            } }
        case "fire":
            for y in 0..<gh { for x in 0..<gw {
                let v = fire[y * gw + x]
                guard v > 2 else { continue }
                let f = CGFloat(v) / 36
                c.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell),
                       NSColor(calibratedRed: min(1, f * 1.6), green: max(0, f * f * 1.2), blue: max(0, f * f * f - 0.3), alpha: 1))
            } }
        default: // aurora
            for band in 0..<4 {
                let path = CGMutablePath()
                let base = CGFloat(band) * 4 + 4
                path.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= c.width {
                    let y = base + 6 * sin(x * 0.012 + CGFloat(t) * (0.6 + Double(band) * 0.2)) + 4 * sin(x * 0.031 - CGFloat(t) * 0.9)
                    path.addLine(to: CGPoint(x: x, y: y + 8))
                    x += 6
                }
                path.addLine(to: CGPoint(x: c.width, y: 0))
                c.cg.addPath(path)
                c.cg.setFillColor(NSColor.hsb(0.35 + CGFloat(band) * 0.12 + CGFloat(sin(t * 0.2)) * 0.05, 0.8, 1, 0.28).cgColor)
                c.cg.fillPath()
            }
        }
        c.text(scenes[scene], x: c.width - 6, y: 1, size: 7, color: NSColor(white: 1, alpha: 0.35), align: .right)
    }

    private func drawNyan(_ c: Canvas) {
        c.fill(c.bounds, NSColor(hex: "#0f2a5c"))
        for i in 0..<40 {
            let sx = (CGFloat(i * 97) - CGFloat(t * 60)).truncatingRemainder(dividingBy: c.width + 20)
            let x = sx < 0 ? sx + c.width + 20 : sx
            let y = CGFloat((i * 37) % 26) + 2
            let tw = (Int(t * 6) + i) % 3
            c.fill(CGRect(x: x, y: y, width: 1 + CGFloat(tw), height: 1), .white)
        }
        let colors = ["#ff0000", "#ff9900", "#ffff00", "#33ff00", "#0099ff", "#6633ff"].map { NSColor(hex: $0) }
        let catY: CGFloat = 8 + 2 * CGFloat(sin(t * 10))
        var x = catX - 2
        while x > -10 {
            let wobble: CGFloat = (Int((catX - x) / 8) % 2 == 0) ? 1 : 0
            for (i, col) in colors.enumerated() { c.fill(CGRect(x: x - 8, y: catY + 13 - CGFloat(i) * 2.2 + wobble, width: 8, height: 2.2), col) }
            x -= 8
        }
        c.sprite(Sprites.cat, x: catX, y: catY, scale: 1.6)
    }

    public func touchBegan(_ t: StripTouch) {
        if scenes[scene] == "life" {
            let gx = Int(t.x / cell)
            for (dx, dy) in [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)] {
                let x = (gx + dx) % max(1, gw), y = (8 + dy) % gh
                life[y * gw + x] = 1
            }
        }
    }

    public func touchEnded(_ t: StripTouch) {
        if abs(t.dx) < 10, t.duration < 0.3, scenes[scene] != "life" || t.x > CGFloat(w) - 80 {
            scene = (scene + 1) % scenes.count
        } else if abs(t.dx) > 60 {
            scene = (scene + (t.dx < 0 ? 1 : scenes.count - 1)) % scenes.count
        }
    }
}
