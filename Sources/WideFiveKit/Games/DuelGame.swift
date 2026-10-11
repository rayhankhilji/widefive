import AppKit

struct DuelClass {
    let name: String, blurb: String, color: NSColor
    let hp: CGFloat, speed: CGFloat, jump: CGFloat, jumps: Int
    let cooldown: Double, bulletSpeed: CGFloat, damage: CGFloat, bulletSize: CGFloat
}

/// Two-player arena shooter across the whole bar. P1 = WASD + F/G, P2 = arrows + / . (S / ↓ = shield).
public final class DuelGame: StripMode, DemoStartable {
    public let id = "duel"
    public let title = "Strip Duel"
    public let icon = "bolt.fill"
    public let isAnimated = true
    public let refreshInterval = 1.0 / 60
    public let allowsGestures = false
    public let showsExitButton = true
    public var isGame: Bool { true }
    public var isTwoPlayer: Bool { true }

    static let classes: [DuelClass] = [
        DuelClass(name: "BLASTER", blurb: "rapid fire · ★ 5-way spread", color: NSColor(hex: "#21e6ff"),
                  hp: 100, speed: 110, jump: 150, jumps: 2, cooldown: 0.2, bulletSpeed: 360, damage: 5, bulletSize: 1.6),
        DuelClass(name: "TANK", blurb: "150 HP, heavy shots · ★ ground quake", color: NSColor(hex: "#ff8a00"),
                  hp: 150, speed: 78, jump: 128, jumps: 1, cooldown: 0.55, bulletSpeed: 250, damage: 14, bulletSize: 3),
        DuelClass(name: "NINJA", blurb: "fast, triple jump · ★ shadow dash", color: NSColor(hex: "#ff2bd6"),
                  hp: 85, speed: 150, jump: 165, jumps: 3, cooldown: 0.28, bulletSpeed: 430, damage: 5, bulletSize: 1.3),
    ]

    enum Phase { case setup, pick, countdown, fight, roundOver, matchOver }

    struct Fighter {
        var cls: Int, x: CGFloat, y: CGFloat = 3, vx: CGFloat = 0, vy: CGFloat = 0
        var facing: CGFloat = 1, hp: CGFloat = 100, energy: CGFloat = 0, cool: Double = 0
        var onGround = true, jumps = 2, blocking = false, flash: Double = 0, invuln: Double = 0, wins = 0
    }
    struct Bullet {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var owner: Int, dmg: CGFloat, size: CGFloat, ground: Bool, color: NSColor, life: Double
    }
    struct Spark { var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: Double, color: NSColor }
    struct Intent { var left = false, right = false, jump = false, fire = false, special = false, block = false }

    private let input = DuoInput()
    private var phase = Phase.setup
    private var vsBot = true
    private var demo = false
    private var focus = 2
    private var picks = [0, 1]
    private var ready = [false, false]
    private var f: [Fighter] = []
    private var bullets: [Bullet] = []
    private var sparks: [Spark] = []
    private var platforms: [CGRect] = []
    private var setupRects: [CGRect] = []
    private var timer: Double = 0
    private var round = 1
    private var lastWinner = 0
    private var width: CGFloat = 1004
    private let ground: CGFloat = 3
    private let gravity: CGFloat = 520

    private var arenaMin: CGFloat { StripController.gameChromeWidth + 4 }
    private var arenaMax: CGFloat { width - 4 }
    private var mid: CGFloat { (arenaMin + arenaMax) / 2 }

    public init() {}

    public func activate(_ ctx: ModeContext) {
        width = ctx.size.width
        input.width = width
        input.layout = ["L", "R", "U", "F", "S"]
        input.reset()
        phase = .setup
        demo = false
    }
    public func deactivate() { input.reset() }
    public func startDemo() { vsBot = true; demo = true; picks = [0, 2]; startMatch() }

    // MARK: flow

    private func goPick() {
        phase = .pick
        ready = [false, vsBot]
        if vsBot { picks[1] = Int.random(in: 0..<Self.classes.count) }
        input.clearEdges()
    }

    private func startMatch() {
        round = 1
        f = []
        startRound()
    }

    private func startRound() {
        let w = arenaMax - arenaMin
        platforms = [
            CGRect(x: mid - w * 0.3 - 55, y: 12, width: 110, height: 2),
            CGRect(x: mid - 45, y: 18, width: 90, height: 2),
            CGRect(x: mid + w * 0.3 - 55, y: 12, width: 110, height: 2),
        ]
        let wins = f.map { $0.wins }
        f = (0..<2).map { p in
            var fi = Fighter(cls: picks[p], x: p == 0 ? arenaMin + 50 : arenaMax - 50)
            fi.facing = p == 0 ? 1 : -1
            fi.hp = Self.classes[picks[p]].hp
            fi.wins = wins.count == 2 ? wins[p] : 0
            return fi
        }
        bullets = []
        phase = .countdown
        timer = 2.2
        input.clearEdges()
    }

    private func players(_ p: Int) -> [Int] { vsBot && p == 0 ? [0, 1] : [p] }
    private func took(_ p: Int, _ b: String) -> Bool { players(p).reduce(false) { input.take($1, b) || $0 } }
    private func down(_ p: Int, _ b: String) -> Bool { players(p).contains { input.isDown($0, b) } }

    // MARK: update

    public func update(dt: Double) {
        let d = CGFloat(min(dt, 1.0 / 20))
        timer -= dt
        sparks = sparks.compactMap { s in
            var s = s
            s.life -= dt; s.x += s.vx * d; s.y += s.vy * d; s.vy -= 200 * d
            return s.life > 0 ? s : nil
        }
        switch phase {
        case .setup:
            for p in 0..<2 {
                if input.take(p, "L") { focus = max(0, focus - 1) }
                if input.take(p, "R") { focus = min(2, focus + 1) }
                if input.take(p, "F") || input.take(p, "U") { pickSetup(focus) }
            }
        case .pick:
            for p in 0..<(vsBot ? 1 : 2) where !ready[p] {
                let n = Self.classes.count
                if took(p, "L") { picks[p] = (picks[p] + n - 1) % n }
                if took(p, "R") { picks[p] = (picks[p] + 1) % n }
                if took(p, "F") || took(p, "U") { ready[p] = true }
            }
            if ready.allSatisfy({ $0 }) { startMatch() }
        case .countdown:
            if timer <= 0 { phase = .fight; input.clearEdges() }
        case .fight:
            simulate(d)
        case .roundOver:
            if timer <= 0 {
                if f.contains(where: { $0.wins >= 2 }) { phase = .matchOver; timer = 1 } else { round += 1; startRound() }
            }
        case .matchOver:
            if demo && timer < -2 { startMatch() }
            if timer <= 0, took(0, "F") || took(1, "F") { phase = .setup; input.clearEdges() }
        }
    }

    private func pickSetup(_ i: Int) {
        switch i {
        case 0: vsBot = true
        case 1: vsBot = false
        default: goPick()
        }
    }

    private func humanIntent(_ p: Int) -> Intent {
        Intent(left: down(p, "L"), right: down(p, "R"), jump: took(p, "U"), fire: down(p, "F"),
               special: took(p, "S"), block: down(p, "D"))
    }

    private func botIntent(_ me: Int) -> Intent {
        var it = Intent()
        let a = f[me], b = f[1 - me]
        let dx = b.x - a.x, dist = abs(dx)
        if dist > 220 { it.right = dx > 0; it.left = dx < 0 } else if dist < 90 { it.left = dx > 0; it.right = dx < 0 }
        if abs(b.y - a.y) < 6, Double.random(in: 0...1) < 0.3 { it.fire = true }
        if b.y > a.y + 6, a.onGround, Double.random(in: 0...1) < 0.04 { it.jump = true }
        for bl in bullets where bl.owner != me {
            let incoming = (bl.vx > 0) == (a.x > bl.x) && abs(bl.x - a.x) < 55
            guard incoming else { continue }
            if bl.ground || abs(bl.y - (a.y + 5)) < 5 {
                if a.onGround, Double.random(in: 0...1) < 0.2 { it.jump = true } else if Double.random(in: 0...1) < 0.08 { it.block = true }
            }
        }
        if a.energy >= 100, dist < 260 { it.special = true }
        if Double.random(in: 0...1) < 0.006 { it.jump = true }
        return it
    }

    private func simulate(_ d: CGFloat) {
        let intents = (0..<2).map { p in (demo || (vsBot && p == 1)) ? botIntent(p) : humanIntent(p) }
        for p in 0..<2 { step(p, intents[p], d) }
        var keep: [Bullet] = []
        for var b in bullets {
            b.x += b.vx * d; b.y += b.vy * d; b.life -= Double(d)
            let t = 1 - b.owner
            let tf = f[t]
            let hitTarget: Bool
            if b.ground { hitTarget = tf.onGround && abs(b.x - tf.x) < 6 } else {
                hitTarget = abs(b.x - tf.x) < 3 + b.size && b.y > tf.y - b.size && b.y < tf.y + 9 + b.size
            }
            if hitTarget, tf.invuln <= 0 { hit(t, b.dmg, dir: b.vx > 0 ? 1 : -1); continue }
            if b.life > 0, b.x > arenaMin, b.x < arenaMax, b.y > 0, b.y < 30 { keep.append(b) }
        }
        bullets = keep
        for p in 0..<2 where f[p].hp <= 0 {
            lastWinner = 1 - p
            f[lastWinner].wins += 1
            burst(f[p].x, f[p].y + 5, Self.classes[f[p].cls].color, 40)
            phase = .roundOver
            timer = 2
            break
        }
    }

    private func step(_ p: Int, _ it: Intent, _ d: CGFloat) {
        var a = f[p]
        let c = Self.classes[a.cls]
        a.cool -= Double(d); a.flash -= Double(d); a.invuln -= Double(d)
        a.energy = min(100, a.energy + 7 * d)
        a.blocking = it.block && a.onGround
        let move: CGFloat = (it.right ? 1 : 0) - (it.left ? 1 : 0)
        let target = a.blocking ? 0 : move * c.speed
        a.vx += (target - a.vx) * min(1, d * 12)
        if it.jump && a.jumps > 0 { a.vy = c.jump; a.jumps -= 1; a.onGround = false }
        a.vy -= gravity * d
        let oldY = a.y
        a.x = min(max(a.x + a.vx * d, arenaMin + 4), arenaMax - 4)
        a.y += a.vy * d
        var landed = false
        if a.y <= ground { a.y = ground; landed = true } else if a.vy <= 0 {
            for pl in platforms where a.x > pl.minX && a.x < pl.maxX && oldY >= pl.maxY && a.y <= pl.maxY {
                a.y = pl.maxY; landed = true
            }
        }
        if landed { a.vy = 0; if !a.onGround { a.jumps = c.jumps }; a.onGround = true } else { a.onGround = false }
        if a.onGround && a.jumps < c.jumps && a.vy == 0 { a.jumps = c.jumps }
        a.facing = f[1 - p].x >= a.x ? 1 : -1
        if it.fire && a.cool <= 0 && !a.blocking {
            a.cool = c.cooldown
            bullets.append(Bullet(x: a.x + a.facing * 6, y: a.y + 5, vx: a.facing * c.bulletSpeed, vy: 0, owner: p,
                                  dmg: c.damage, size: c.bulletSize, ground: false, color: c.color, life: 3))
        }
        let special = it.special && a.energy >= 100
        if special { a.energy = 0 }
        f[p] = a
        if special { doSpecial(p) }
    }

    private func doSpecial(_ p: Int) {
        let a = f[p]
        let c = Self.classes[a.cls]
        switch a.cls {
        case 0:
            for k in -2...2 {
                bullets.append(Bullet(x: a.x + a.facing * 6, y: a.y + 5, vx: a.facing * 380, vy: CGFloat(k) * 40, owner: p,
                                      dmg: 8, size: 2, ground: false, color: .white, life: 2))
            }
        case 1:
            for dir: CGFloat in [-1, 1] {
                bullets.append(Bullet(x: a.x, y: ground + 1, vx: dir * 300, vy: 0, owner: p,
                                      dmg: 20, size: 4, ground: true, color: c.color, life: 1.3))
            }
            burst(a.x, ground, c.color, 30)
        default:
            let from = a.x
            let to = min(max(a.x + a.facing * 170, arenaMin + 4), arenaMax - 4)
            f[p].x = to
            f[p].invuln = 0.45
            for k in 0..<14 { burst(from + (to - from) * CGFloat(k) / 14, a.y + 5, c.color, 1) }
            let o = f[1 - p]
            if (min(from, to)...max(from, to)).contains(o.x), abs(o.y - a.y) < 12 { hit(1 - p, 22, dir: a.facing) }
        }
    }

    private func hit(_ t: Int, _ dmg: CGFloat, dir: CGFloat) {
        guard f[t].invuln <= 0 else { return }
        let dealt = f[t].blocking ? dmg * 0.25 : dmg
        f[t].hp -= dealt
        f[t].flash = 0.15
        f[t].vx += dir * (f[t].blocking ? 40 : 140)
        f[1 - t].energy = min(100, f[1 - t].energy + dealt * 1.5)
        f[t].energy = min(100, f[t].energy + dealt * 0.5)
        burst(f[t].x, f[t].y + 5, f[t].blocking ? Pal.cyan : .white, 10)
    }

    private func burst(_ x: CGFloat, _ y: CGFloat, _ color: NSColor, _ n: Int) {
        for _ in 0..<n {
            let a = CGFloat.random(in: 0...(2 * .pi)), v = CGFloat.random(in: 20...120)
            sparks.append(Spark(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v, life: Double.random(in: 0.2...0.6), color: color))
        }
    }

    // MARK: touch

    public func touchBegan(_ t: StripTouch) {
        switch phase {
        case .setup:
            if let i = setupRects.firstIndex(where: { t.x >= $0.minX && t.x <= $0.maxX }) { focus = i; pickSetup(i) }
        case .pick:
            let p = t.x < mid ? 0 : 1
            guard p == 0 || !vsBot else { return }
            let h0 = p == 0 ? arenaMin : mid, h1 = p == 0 ? mid : arenaMax
            let n = Self.classes.count
            if t.x < h0 + (h1 - h0) * 0.18 { picks[p] = (picks[p] + n - 1) % n; ready[p] = false } else if t.x > h1 - (h1 - h0) * 0.18 { picks[p] = (picks[p] + 1) % n; ready[p] = false } else { ready[p].toggle() }
            if ready.allSatisfy({ $0 }) { startMatch() }
        case .matchOver:
            if timer <= 0 { phase = .setup }
        default:
            input.began(t)
        }
    }
    public func touchMoved(_ t: StripTouch) { input.moved(t) }
    public func touchEnded(_ t: StripTouch) { input.ended(t) }
    public func touchCancelled(_ t: StripTouch) { input.ended(t) }
    public func keyDown(_ key: GameKey) { input.key(key, down: true) }
    public func keyUp(_ key: GameKey) { input.key(key, down: false) }

    // MARK: draw

    public func draw(_ c: Canvas) {
        width = c.width
        input.width = width
        input.players = vsBot ? 1 : 2
        c.gradient(c.bounds, [NSColor(hex: "#2a0b3d"), NSColor(hex: "#07021a")])
        for i in stride(from: arenaMin, to: arenaMax, by: 28) {
            c.fill(CGRect(x: i, y: 0, width: 0.5, height: ground), NSColor(white: 1, alpha: 0.12))
        }
        c.fill(CGRect(x: arenaMin, y: ground - 0.8, width: arenaMax - arenaMin, height: 0.8), Pal.cyan.withAlphaComponent(0.7))
        switch phase {
        case .setup: drawSetup(c); return
        case .pick: drawPick(c); return
        default: break
        }
        for pl in platforms {
            c.fill(pl, Pal.magenta.withAlphaComponent(0.85))
            c.fill(CGRect(x: pl.minX, y: pl.minY - 2, width: pl.width, height: 2), Pal.magenta.withAlphaComponent(0.15))
        }
        for b in bullets {
            if b.ground {
                c.fill(CGRect(x: b.x - 6, y: ground, width: 12, height: 3 + CGFloat.random(in: 0...2)), b.color.withAlphaComponent(0.85))
            } else {
                c.fill(CGRect(x: b.x - b.size - abs(b.vx) * 0.012, y: b.y - b.size / 2, width: abs(b.vx) * 0.012, height: b.size), b.color.withAlphaComponent(0.35))
                c.circle(center: CGPoint(x: b.x, y: b.y), radius: b.size, b.color)
            }
        }
        for (p, fi) in f.enumerated() { drawFighter(c, fi, label: p == 0 ? "P1" : (vsBot ? "BOT" : "P2")) }
        for s in sparks { c.fill(CGRect(x: s.x, y: s.y, width: 1.4, height: 1.4), s.color.withAlphaComponent(CGFloat(min(1, s.life * 3)))) }
        drawHUD(c)
        switch phase {
        case .countdown:
            let n = Int(ceil(timer / 0.7))
            Arcade.banner(c, n > 0 ? "ROUND \(round) · \(n)" : "FIGHT!", "P1 WASD F G · P2 ← → ↑ / .", accent: Pal.yellow, width: 280)
        case .roundOver:
            Arcade.banner(c, "\(name(lastWinner)) TAKES ROUND \(round)", "\(f[0].wins) – \(f[1].wins)", accent: Self.classes[f[lastWinner].cls].color, width: 300)
        case .matchOver:
            Arcade.banner(c, "🏆 \(name(lastWinner)) WINS", "tap or F to play again", accent: Self.classes[f[lastWinner].cls].color, width: 300)
        default: break
        }
        input.draw(c, colors: f.map { Self.classes[$0.cls].color })
    }

    private func name(_ p: Int) -> String { p == 0 ? "P1" : (vsBot ? "BOT" : "P2") }

    private func drawFighter(_ c: Canvas, _ fi: Fighter, label: String) {
        let cl = Self.classes[fi.cls]
        if fi.invuln > 0, Int(c.time * 30) % 2 == 0 { return }
        let col = fi.flash > 0 ? NSColor.white : cl.color
        let w: CGFloat = fi.cls == 1 ? 8 : 6, h: CGFloat = fi.cls == 2 ? 8 : 9
        let x = fi.x, y = fi.y
        let walking = abs(fi.vx) > 10 && fi.onGround
        let legShift: CGFloat = walking && Int(c.time * 12) % 2 == 0 ? 1 : 0
        c.fill(CGRect(x: x - w / 2 + legShift, y: y, width: 1.6, height: 2), col.blended(withFraction: 0.4, of: .black) ?? col)
        c.fill(CGRect(x: x + w / 2 - 1.6 - legShift, y: y, width: 1.6, height: 2), col.blended(withFraction: 0.4, of: .black) ?? col)
        c.fill(CGRect(x: x - w / 2, y: y + 2, width: w, height: h * 0.45), col)
        c.fill(CGRect(x: x - w / 2 + 1, y: y + 2 + h * 0.45, width: w - 2, height: h * 0.4), col.blended(withFraction: 0.35, of: .white) ?? col)
        c.fill(CGRect(x: x + fi.facing * (w / 2 - 2.2) - 0.6, y: y + 2 + h * 0.62, width: 1.3, height: 1.3), .black)
        let gunW: CGFloat = fi.cls == 1 ? 5 : 4
        c.fill(CGRect(x: fi.facing > 0 ? x + w / 2 - 1 : x - w / 2 - gunW + 1, y: y + 2 + h * 0.25, width: gunW, height: fi.cls == 1 ? 2 : 1.3), NSColor(white: 0.85, alpha: 1))
        if fi.cls == 2 {
            c.fill(CGRect(x: x - w / 2 + 1, y: y + 2 + h * 0.72, width: w - 2, height: 0.9), Pal.red)
            c.fill(CGRect(x: fi.facing > 0 ? x - w / 2 - 3 : x + w / 2 - 1, y: y + 2 + h * 0.7 + sin(CGFloat(c.time) * 14), width: 4, height: 0.9), Pal.red)
        }
        if fi.blocking {
            c.roundRect(CGRect(x: x - w / 2 - 3, y: y - 1, width: w + 6, height: h + 5), radius: 4, fill: Pal.cyan.withAlphaComponent(0.15), stroke: Pal.cyan, lineWidth: 0.8)
        }
        if y < 15 { c.text(label, x: x, y: y + h + 3, size: 5.5, color: NSColor(white: 1, alpha: 0.7), weight: .bold, align: .center) }
    }

    private func drawHUD(_ c: Canvas) {
        guard f.count == 2 else { return }
        let barW: CGFloat = min(170, (arenaMax - arenaMin) / 2 - 60)
        for p in 0..<2 {
            let fi = f[p], cl = Self.classes[fi.cls]
            let frac = max(0, fi.hp / cl.hp)
            let x0 = p == 0 ? mid - 26 - barW : mid + 26
            c.fill(CGRect(x: x0, y: 25.5, width: barW, height: 3), NSColor(white: 1, alpha: 0.12))
            let fw = barW * frac
            c.fill(CGRect(x: p == 0 ? x0 + barW - fw : x0, y: 25.5, width: fw, height: 3), frac < 0.3 ? Pal.red : cl.color)
            let ew = barW * 0.6 * fi.energy / 100
            c.fill(CGRect(x: p == 0 ? x0 + barW - ew : x0, y: 23.5, width: ew, height: 1.2), fi.energy >= 100 ? Pal.yellow : NSColor(white: 1, alpha: 0.5))
            for w in 0..<2 {
                let dx = p == 0 ? mid - 18 + CGFloat(w) * 5 : mid + 9 + CGFloat(w) * 5
                c.fill(CGRect(x: dx, y: 25, width: 3, height: 3), w < fi.wins ? Pal.yellow : NSColor(white: 1, alpha: 0.2))
            }
        }
    }

    private func drawSetup(_ c: Canvas) {
        c.text("STRIP", x: arenaMin + 4, y: 15, size: 9, color: Pal.cyan, weight: .black)
        c.text("DUEL", x: arenaMin + 4, y: 4, size: 11, color: Pal.magenta, weight: .black)
        var x = arenaMin + 50
        setupRects = []
        for (i, label) in ["VS BOT", "VS FRIEND", "FIGHT ▶"].enumerated() {
            let w: CGFloat = i == 2 ? 92 : 84
            let r = CGRect(x: x, y: 3, width: w, height: 24)
            let sel = (i == 0 && vsBot) || (i == 1 && !vsBot)
            let fill = i == 2 ? Pal.magenta.withAlphaComponent(0.85) : sel ? Pal.cyan.withAlphaComponent(0.75) : NSColor(white: 0.12, alpha: 1)
            c.roundRect(r, radius: 7, fill: fill, stroke: focus == i ? .white : nil, lineWidth: 1.2)
            c.text(label, x: r.midX, size: 9, color: sel || i == 2 ? .black : .white, weight: .heavy, align: .center)
            setupRects.append(r)
            x += w + 6
        }
        c.text("P1  WASD · F shoot · G special · S shield      P2  arrows · / shoot · . special · ↓ shield      ⌃⌥⌘K locks keys",
               x: x + 8, size: 8, color: NSColor(white: 0.65, alpha: 1), maxWidth: c.width - x - 14)
    }

    private func drawPick(_ c: Canvas) {
        for p in 0..<2 {
            let h0 = p == 0 ? arenaMin : mid + 2, h1 = p == 0 ? mid - 2 : arenaMax
            let cl = Self.classes[picks[p]]
            c.roundRect(CGRect(x: h0, y: 1, width: h1 - h0, height: 28), radius: 7, fill: NSColor(white: 0.06, alpha: 0.9),
                        stroke: ready[p] ? Pal.yellow : cl.color.withAlphaComponent(0.6), lineWidth: ready[p] ? 1.5 : 1)
            c.text("◀", x: h0 + 12, size: 12, color: cl.color, weight: .heavy, align: .center)
            c.text("▶", x: h1 - 12, size: 12, color: cl.color, weight: .heavy, align: .center)
            var demoFighter = Fighter(cls: picks[p], x: h0 + 44)
            demoFighter.y = 6
            demoFighter.facing = 1
            demoFighter.vx = 20
            drawFighter(c, demoFighter, label: "")
            let who = p == 0 ? "P1" : (vsBot ? "BOT" : "P2")
            c.text("\(who) · \(cl.name)", x: h0 + 64, y: 16, size: 10, color: .white, weight: .black)
            c.text(cl.blurb, x: h0 + 64, y: 5, size: 8, color: cl.color, weight: .semibold, maxWidth: h1 - h0 - 150)
            let tag = ready[p] ? "READY ✓" : (p == 1 && vsBot ? "" : "F / tap = ready")
            c.text(tag, x: h1 - 26, size: 8, color: ready[p] ? Pal.yellow : NSColor(white: 0.6, alpha: 1), weight: .bold, align: .right)
        }
    }
}
