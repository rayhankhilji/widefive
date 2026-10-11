import AppKit

struct DuelClass {
    let name: String, blurb: String, special: String, color: NSColor, dark: NSColor
    let hp: CGFloat, speed: CGFloat, jump: CGFloat, jumps: Int
    let cooldown: Double, bulletSpeed: CGFloat, damage: CGFloat, bulletSize: CGFloat
    /// 1…5 ratings for the select screen: HP, SPD, PWR.
    let stats: [Int]
}

struct DuelArena {
    let name: String, accent: NSColor
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
        DuelClass(name: "BLASTER", blurb: "rapid fire · double jump", special: "5-WAY SPREAD", color: NSColor(hex: "#21e6ff"), dark: NSColor(hex: "#0b5b78"),
                  hp: 100, speed: 112, jump: 138, jumps: 2, cooldown: 0.2, bulletSpeed: 360, damage: 5, bulletSize: 1.6, stats: [3, 3, 3]),
        DuelClass(name: "TANK", blurb: "150 HP · heavy shells", special: "GROUND QUAKE", color: NSColor(hex: "#ff8a00"), dark: NSColor(hex: "#7a3300"),
                  hp: 150, speed: 80, jump: 120, jumps: 1, cooldown: 0.55, bulletSpeed: 250, damage: 14, bulletSize: 2.6, stats: [5, 1, 5]),
        DuelClass(name: "NINJA", blurb: "fast · triple jump · shuriken", special: "SHADOW DASH", color: NSColor(hex: "#ff2bd6"), dark: NSColor(hex: "#3b3270"),
                  hp: 85, speed: 150, jump: 146, jumps: 3, cooldown: 0.28, bulletSpeed: 430, damage: 5, bulletSize: 1.8, stats: [2, 5, 2]),
    ]
    static let arenas: [DuelArena] = [
        DuelArena(name: "NEON CITY", accent: NSColor(hex: "#ff2bd6")),
        DuelArena(name: "SUNSET DOJO", accent: NSColor(hex: "#ffb347")),
        DuelArena(name: "MOLTEN CORE", accent: NSColor(hex: "#ff5a1f")),
    ]

    enum Phase { case setup, pick, countdown, fight, roundOver, matchOver }

    struct Fighter {
        var cls: Int, x: CGFloat, y: CGFloat = 3, vx: CGFloat = 0, vy: CGFloat = 0
        var facing: CGFloat = 1, hp: CGFloat = 100, chip: CGFloat = 100, energy: CGFloat = 0, cool: Double = 0
        var onGround = true, jumps = 2, blocking = false, flash: Double = 0, invuln: Double = 0, wins = 0
        var muzzle: Double = 0, hurtT: Double = 0, chipDelay: Double = 0, landT: Double = 0
    }
    struct Bullet {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var owner: Int, dmg: CGFloat, size: CGFloat, ground: Bool, color: NSColor, life: Double
        var kind: Int, special = false
    }
    struct Ghost { var x: CGFloat, y: CGFloat, facing: CGFloat, cls: Int, life: Double }
    struct Intent { var left = false, right = false, jump = false, fire = false, special = false, block = false }

    private let input = DuoInput()
    private var phase = Phase.setup
    private var vsBot = true
    private var demo = false
    private var focus = 3
    private var arena = 0
    private var picks = [0, 1]
    private var ready = [false, false]
    private var f: [Fighter] = []
    private var bullets: [Bullet] = []
    private var ghosts: [Ghost] = []
    private var platforms: [CGRect] = []
    private var setupRects: [CGRect] = []
    private var timer: Double = 0
    private var t: Double = 0
    private var phaseT: Double = 0
    private var fightT: Double = -9
    private var koT: Double = -9
    private var hitStop: Double = 0
    private var slowmo: Double = 0
    private var round = 1
    private var lastWinner = 0
    private var width: CGFloat = 1004
    private let ground: CGFloat = 3
    private let ceiling: CGFloat = 13
    private let gravity: CGFloat = 500
    private let particles = Particles()
    private let shake = Shake(maxOffset: 3)
    private var pops: [Arcade.Popup] = []

    private var arenaMin: CGFloat { StripController.gameChromeWidth + 4 }
    private var arenaMax: CGFloat { width - 4 }
    private var mid: CGFloat { (arenaMin + arenaMax) / 2 }

    public init() {}

    public func activate(_ ctx: ModeContext) {
        width = ctx.size.width
        input.width = width
        input.layout = ["L", "R", "U", "F", "S"]
        input.reset()
        setPhase(.setup)
        demo = false
    }
    public func deactivate() { input.reset() }
    public func startDemo() { vsBot = true; demo = true; picks = [0, 2]; startMatch() }

    private func setPhase(_ p: Phase) { phase = p; phaseT = t }

    // MARK: flow

    private func goPick() {
        setPhase(.pick)
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
            CGRect(x: mid - w * 0.3 - 55, y: 7.5, width: 110, height: 1.8),
            CGRect(x: mid - 45, y: 11, width: 90, height: 1.8),
            CGRect(x: mid + w * 0.3 - 55, y: 7.5, width: 110, height: 1.8),
        ]
        let wins = f.map { $0.wins }
        f = (0..<2).map { p in
            var fi = Fighter(cls: picks[p], x: p == 0 ? arenaMin + 60 : arenaMax - 60)
            fi.facing = p == 0 ? 1 : -1
            fi.hp = Self.classes[picks[p]].hp
            fi.chip = fi.hp
            fi.wins = wins.count == 2 ? wins[p] : 0
            return fi
        }
        bullets = []; ghosts = []
        setPhase(.countdown)
        timer = 2.4
        input.clearEdges()
    }

    private func players(_ p: Int) -> [Int] { vsBot && p == 0 ? [0, 1] : [p] }
    private func took(_ p: Int, _ b: String) -> Bool { players(p).reduce(false) { input.take($1, b) || $0 } }
    private func down(_ p: Int, _ b: String) -> Bool { players(p).contains { input.isDown($0, b) } }

    // MARK: update

    public func update(dt: Double) {
        t += dt
        Arcade.update(&pops, dt)
        shake.update(CGFloat(dt))
        var dt = dt
        if hitStop > 0 { hitStop -= dt; particles.update(CGFloat(dt) * 0.15); return }
        if slowmo > 0 { slowmo -= dt; dt *= 0.3 }
        let d = CGFloat(min(dt, 1.0 / 20))
        timer -= dt
        particles.update(d)
        for i in ghosts.indices { ghosts[i].life -= dt }
        ghosts.removeAll { $0.life <= 0 }
        for i in f.indices {
            f[i].chipDelay -= dt
            if f[i].chipDelay <= 0 { f[i].chip = max(f[i].hp, f[i].chip - 90 * d) }
        }
        switch phase {
        case .setup:
            for p in 0..<2 {
                if input.take(p, "L") { focus = max(0, focus - 1) }
                if input.take(p, "R") { focus = min(3, focus + 1) }
                if input.take(p, "F") || input.take(p, "U") { pickSetup(focus) }
            }
        case .pick:
            for p in 0..<(vsBot ? 1 : 2) where !ready[p] {
                let n = Self.classes.count
                if took(p, "L") { picks[p] = (picks[p] + n - 1) % n }
                if took(p, "R") { picks[p] = (picks[p] + 1) % n }
                if took(p, "F") || took(p, "U") { ready[p] = true; readyBurst(p) }
            }
            if ready.allSatisfy({ $0 }), t - phaseT > 0.2 { startMatch() }
        case .countdown:
            idle(d)
            if timer <= 0 { setPhase(.fight); fightT = t; input.clearEdges() }
        case .fight:
            simulate(d)
        case .roundOver:
            idle(d)
            if timer <= 0 {
                if f.contains(where: { $0.wins >= 2 }) { setPhase(.matchOver); timer = 1 } else { round += 1; startRound() }
            }
        case .matchOver:
            idle(d)
            if demo && timer < -2.5 { startMatch() }
            if timer <= 0, took(0, "F") || took(1, "F") { setPhase(.setup); input.clearEdges() }
        }
    }

    private func readyBurst(_ p: Int) {
        let x = p == 0 ? mid - 120 : mid + 120
        particles.burst(x: x, y: 15, count: 24, colors: [Self.classes[picks[p]].color, .white, NSColor(hex: "#ffd23f")], speed: 90, life: 0.6, size: 1.6, gravity: 0, kind: .sparkle, drag: 3)
        shake.add(0.2)
    }

    /// Keeps physics alive between rounds so fighters land / the loser falls.
    private func idle(_ d: CGFloat) {
        for p in f.indices { step(p, Intent(), d) }
    }

    private func pickSetup(_ i: Int) {
        switch i {
        case 0: vsBot = true
        case 1: vsBot = false
        case 2: arena = (arena + 1) % Self.arenas.count
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
        if b.y > a.y + 5, a.onGround, Double.random(in: 0...1) < 0.04 { it.jump = true }
        for bl in bullets where bl.owner != me {
            let incoming = (bl.vx > 0) == (a.x > bl.x) && abs(bl.x - a.x) < 55
            guard incoming else { continue }
            if bl.ground || abs(bl.y - (a.y + 9)) < 7 {
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
            if b.kind == 1, !b.ground, Int(t * 60) % 3 == 0 {
                particles.burst(x: b.x - b.vx * 0.01, y: b.y, count: 1, colors: [NSColor(white: 0.6, alpha: 0.5)], speed: 6, life: 0.4, size: 1.6, gravity: 10, kind: .glow, drag: 2)
            }
            if b.ground, Int(t * 60) % 2 == 0 {
                particles.burst(x: b.x, y: ground + 1, count: 2, colors: [b.color, NSColor(hex: "#8a6a4a")], speed: 50, life: 0.5, size: 1.4, gravity: -260, kind: .shard, upBias: 0.9)
            }
            let tgt = 1 - b.owner
            let tf = f[tgt]
            let hitTarget: Bool
            if b.ground { hitTarget = tf.onGround && abs(b.x - tf.x) < 7 } else {
                hitTarget = abs(b.x - tf.x) < 3.5 + b.size && b.y > tf.y - b.size && b.y < tf.y + 15.5 + b.size
            }
            if hitTarget, tf.invuln <= 0 { hit(tgt, b.dmg, dir: b.vx > 0 ? 1 : -1, at: CGPoint(x: b.x, y: b.y), color: b.color, heavy: b.kind == 1 || b.special); continue }
            if b.life > 0, b.x > arenaMin, b.x < arenaMax, b.y > 0, b.y < 30 { keep.append(b) } else if b.x <= arenaMin || b.x >= arenaMax {
                particles.burst(x: b.x, y: b.y, count: 4, colors: [b.color], speed: 40, life: 0.25, size: 1, gravity: 0, kind: .streak, drag: 4)
            }
        }
        bullets = keep
        for p in 0..<2 where f[p].hp <= 0 {
            lastWinner = 1 - p
            f[lastWinner].wins += 1
            let cl = Self.classes[f[p].cls]
            particles.burst(x: f[p].x, y: f[p].y + 7, count: 50, colors: [cl.color, .white, NSColor(hex: "#ffd23f")], speed: 130, life: 0.9, size: 2, gravity: -60, kind: .shard, drag: 2)
            particles.flash(x: f[p].x, y: f[p].y + 7, color: .white, radius: 60, life: 0.3)
            particles.ring(x: f[p].x, y: f[p].y + 7, color: cl.color, radius: 30, life: 0.5)
            f[p].vy = 120; f[p].vx = (f[p].x < f[lastWinner].x ? -1 : 1) * 90; f[p].onGround = false
            shake.add(1); hitStop = 0.22; slowmo = 0.9; koT = t
            setPhase(.roundOver)
            timer = 2.6
            break
        }
    }

    private func step(_ p: Int, _ it: Intent, _ d: CGFloat) {
        var a = f[p]
        let c = Self.classes[a.cls]
        let dead = a.hp <= 0
        a.cool -= Double(d); a.flash -= Double(d); a.invuln -= Double(d); a.muzzle -= Double(d)
        if phase == .fight { a.energy = min(100, a.energy + 7 * d) }
        a.blocking = it.block && a.onGround
        let move: CGFloat = (it.right ? 1 : 0) - (it.left ? 1 : 0)
        let target = a.blocking || dead ? 0 : move * c.speed
        a.vx += (target - a.vx) * min(1, d * (a.onGround ? 12 : 5))
        if it.jump && a.jumps > 0 {
            a.vy = c.jump; a.jumps -= 1
            particles.burst(x: a.x, y: a.y, count: a.onGround ? 6 : 8, colors: [a.onGround ? NSColor(white: 0.85, alpha: 0.7) : c.color], speed: 30, life: 0.3, size: 1.3, gravity: 0,
                            kind: a.onGround ? .dot : .ring, drag: 4, direction: -.pi / 2, spread: a.onGround ? 3 : 1)
            a.onGround = false
        }
        a.vy -= gravity * d
        let oldY = a.y
        a.x = min(max(a.x + a.vx * d, arenaMin + 5), arenaMax - 5)
        a.y += a.vy * d
        if a.y > ceiling { a.y = ceiling; a.vy = min(a.vy, 0) }
        var landed = false
        if a.y <= ground { a.y = ground; landed = true } else if a.vy <= 0, !dead {
            for pl in platforms where a.x > pl.minX && a.x < pl.maxX && oldY >= pl.maxY && a.y <= pl.maxY {
                a.y = pl.maxY; landed = true
            }
        }
        if landed {
            if !a.onGround, a.vy < -90 {
                a.landT = t
                particles.burst(x: a.x, y: a.y, count: 6, colors: [NSColor(white: 0.85, alpha: 0.6)], speed: 35, life: 0.3, size: 1.2, gravity: 0, kind: .dot, drag: 5, direction: .pi / 2, spread: 3)
            }
            a.vy = 0; if !a.onGround { a.jumps = c.jumps }; a.onGround = true
        } else { a.onGround = false }
        if a.onGround && a.jumps < c.jumps && a.vy == 0 { a.jumps = c.jumps }
        if !dead { a.facing = f[1 - p].x >= a.x ? 1 : -1 }
        if it.fire && a.cool <= 0 && !a.blocking && !dead {
            a.cool = c.cooldown
            a.muzzle = 0.07
            let gy = a.y + (a.cls == 1 ? 9.2 : 10.2)
            let gx = a.x + a.facing * (a.cls == 1 ? 12 : 11)
            bullets.append(Bullet(x: gx, y: gy, vx: a.facing * c.bulletSpeed, vy: 0, owner: p,
                                  dmg: c.damage, size: c.bulletSize, ground: false, color: c.color, life: 3, kind: a.cls))
            particles.flash(x: gx, y: gy, color: c.color, radius: a.cls == 1 ? 9 : 6, life: 0.08)
            if a.cls == 1 {
                a.vx -= a.facing * 40; shake.add(0.08)
                particles.burst(x: gx, y: gy, count: 5, colors: [NSColor(white: 0.7, alpha: 0.5)], speed: 20, life: 0.5, size: 2, gravity: 15, kind: .glow, drag: 3)
            }
        }
        let special = it.special && a.energy >= 100 && !dead
        if special { a.energy = 0 }
        f[p] = a
        if special { doSpecial(p) }
    }

    private func doSpecial(_ p: Int) {
        let a = f[p]
        let c = Self.classes[a.cls]
        pops.append(.init(x: a.x, y: a.y + 16, text: "★ " + c.special, color: c.color, life: 1))
        particles.ring(x: a.x, y: a.y + 7, color: c.color, radius: 22, life: 0.4)
        shake.add(0.35)
        switch a.cls {
        case 0:
            for k in -2...2 {
                bullets.append(Bullet(x: a.x + a.facing * 11, y: a.y + 10.2, vx: a.facing * 380, vy: CGFloat(k) * 40, owner: p,
                                      dmg: 8, size: 2, ground: false, color: .white, life: 2, kind: 0, special: true))
            }
            particles.flash(x: a.x + a.facing * 11, y: a.y + 10, color: c.color, radius: 22, life: 0.18)
        case 1:
            for dir: CGFloat in [-1, 1] {
                bullets.append(Bullet(x: a.x, y: ground + 1, vx: dir * 300, vy: 0, owner: p,
                                      dmg: 20, size: 4, ground: true, color: c.color, life: 1.3, kind: 1, special: true))
            }
            shake.add(0.6)
            particles.burst(x: a.x, y: ground, count: 30, colors: [c.color, NSColor(hex: "#8a6a4a"), .white], speed: 90, life: 0.7, size: 1.8, gravity: -260, kind: .shard, upBias: 0.9)
        default:
            let from = a.x
            let to = min(max(a.x + a.facing * 170, arenaMin + 5), arenaMax - 5)
            for k in 0..<8 { ghosts.append(Ghost(x: from + (to - from) * CGFloat(k) / 8, y: a.y, facing: a.facing, cls: a.cls, life: 0.15 + Double(k) * 0.04)) }
            f[p].x = to
            f[p].invuln = 0.45
            particles.burst(x: (from + to) / 2, y: a.y + 7, count: 26, colors: [c.color, NSColor(hex: "#7b2cff")], speed: 40, life: 0.5, size: 1.4, gravity: 0, kind: .streak, drag: 3,
                            direction: a.facing > 0 ? 0 : .pi, spread: 0.6)
            let o = f[1 - p]
            if (min(from, to)...max(from, to)).contains(o.x), abs(o.y - a.y) < 12 {
                hit(1 - p, 22, dir: a.facing, at: CGPoint(x: o.x, y: o.y + 7), color: c.color, heavy: true)
            }
        }
    }

    private func hit(_ tgt: Int, _ dmg: CGFloat, dir: CGFloat, at pt: CGPoint, color: NSColor, heavy: Bool) {
        guard f[tgt].invuln <= 0 else { return }
        let blocked = f[tgt].blocking
        let dealt = blocked ? dmg * 0.25 : dmg
        if f[tgt].chipDelay <= 0 { f[tgt].chip = max(f[tgt].chip, f[tgt].hp) }
        f[tgt].hp -= dealt
        f[tgt].chipDelay = 0.5
        f[tgt].flash = 0.12
        f[tgt].hurtT = t
        f[tgt].vx += dir * (blocked ? 40 : heavy ? 220 : 140)
        if heavy, !blocked { f[tgt].vy = max(f[tgt].vy, 70) }
        f[1 - tgt].energy = min(100, f[1 - tgt].energy + dealt * 1.5)
        f[tgt].energy = min(100, f[tgt].energy + dealt * 0.5)
        if blocked {
            particles.burst(x: pt.x, y: pt.y, count: 8, colors: [Pal.cyan, .white], speed: 60, life: 0.25, size: 1, gravity: 0, kind: .streak, drag: 4)
            particles.ring(x: f[tgt].x, y: f[tgt].y + 7, color: Pal.cyan, radius: 10, life: 0.2)
            pops.append(.init(x: f[tgt].x, y: f[tgt].y + 15, text: "BLOCK", color: Pal.cyan, life: 0.6))
        } else {
            hitStop = max(hitStop, heavy ? 0.07 : 0.035)
            shake.add(heavy ? 0.4 : 0.14)
            particles.burst(x: pt.x, y: pt.y, count: heavy ? 18 : 10, colors: [color, .white, NSColor(hex: "#ffd23f")], speed: heavy ? 110 : 80, life: 0.35, size: 1.3, gravity: 0, kind: .streak, drag: 4,
                            direction: dir > 0 ? 0 : .pi, spread: 2.2)
            particles.flash(x: pt.x, y: pt.y, color: .white, radius: heavy ? 14 : 8, life: 0.08)
            pops.append(.init(x: f[tgt].x + CGFloat.random(in: -4...4), y: f[tgt].y + 15, text: "\(Int(dealt.rounded()))", color: heavy ? NSColor(hex: "#ffd23f") : .white, life: 0.7))
        }
    }

    // MARK: touch

    public func touchBegan(_ tch: StripTouch) {
        switch phase {
        case .setup:
            if let i = setupRects.firstIndex(where: { tch.x >= $0.minX && tch.x <= $0.maxX }) { focus = i; pickSetup(i) }
        case .pick:
            let p = tch.x < mid ? 0 : 1
            guard p == 0 || !vsBot else { return }
            let h0 = p == 0 ? arenaMin : mid, h1 = p == 0 ? mid : arenaMax
            let n = Self.classes.count
            if tch.x < h0 + (h1 - h0) * 0.18 { picks[p] = (picks[p] + n - 1) % n; ready[p] = false } else if tch.x > h1 - (h1 - h0) * 0.18 { picks[p] = (picks[p] + 1) % n; ready[p] = false } else {
                ready[p].toggle(); if ready[p] { readyBurst(p) }
            }
            if ready.allSatisfy({ $0 }) { startMatch() }
        case .matchOver:
            if timer <= 0 { setPhase(.setup) }
        default:
            input.began(tch)
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
        c.cg.saveGState()
        shake.apply(c)
        drawArena(c, arena, dim: phase == .setup || phase == .pick)
        switch phase {
        case .setup: c.cg.restoreGState(); drawSetup(c); particles.draw(c, camX: 0); return
        case .pick: c.cg.restoreGState(); drawPick(c); particles.draw(c, camX: 0); return
        default: break
        }
        for pl in platforms { drawPlatform(c, pl) }
        for g in ghosts {
            var gf = Fighter(cls: g.cls, x: g.x); gf.y = g.y; gf.facing = g.facing; gf.vx = 150
            drawFighter(c, gf, label: "", ghost: CGFloat(g.life / 0.45))
        }
        for (p, fi) in f.enumerated() { drawShadow(c, fi); drawFighter(c, fi, label: name(p), labelColor: p == 0 ? Pal.cyan : Pal.magenta) }
        for b in bullets { drawBullet(c, b) }
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.3)
        drawHUD(c)
        drawAnnouncer(c)
        if !demo, !input.usedKeyboard, phase == .fight || phase == .countdown { input.draw(c, colors: f.map { Self.classes[$0.cls].color }) }
    }

    private func name(_ p: Int) -> String { p == 0 ? "P1" : (vsBot ? "BOT" : "P2") }

    // MARK: arenas

    private func drawArena(_ c: Canvas, _ idx: Int, dim: Bool) {
        let w = c.width
        switch idx {
        case 1: // Sunset dojo
            c.gradient(c.bounds, [NSColor(hex: "#ffcf7a"), NSColor(hex: "#ff7b6b"), NSColor(hex: "#6b2e6e")].reversed())
            let sun = CGPoint(x: w * 0.5, y: 13)
            Glow.radial(c, sun, 70, NSColor(hex: "#fff0b8"), alpha: 0.6)
            c.circle(center: sun, radius: 12, NSColor(hex: "#fff3c4"))
            for k in 0..<4 { c.fill(CGRect(x: sun.x - 13, y: 4 + CGFloat(k) * 2.4, width: 26, height: 0.7 + CGFloat(k) * 0.15), NSColor(hex: "#ff9d7a", alpha: 0.8)) }
            var mx: CGFloat = -20
            var i = 0
            while mx < w { // mountains
                let h: CGFloat = 8 + CGFloat((i * 37) % 9)
                c.polygon([CGPoint(x: mx, y: 0), CGPoint(x: mx + 45, y: h + 2), CGPoint(x: mx + 95, y: 0)], NSColor(hex: "#8a3f6b", alpha: 0.75))
                mx += 70; i += 1
            }
            for px in [w * 0.18, w * 0.8] { pagoda(c, x: px, color: NSColor(hex: "#4a1f45")) }
            for k in 0..<24 { // petals
                let px = (CGFloat(k) * 97 + CGFloat(t) * 18).truncatingRemainder(dividingBy: w)
                let py = 30 - (CGFloat(k) * 7 + CGFloat(t) * 6).truncatingRemainder(dividingBy: 30)
                c.cg.saveGState(); c.cg.translateBy(x: px + CGFloat(sin(t + Double(k))) * 4, y: py); c.cg.rotate(by: CGFloat(t * 2) + CGFloat(k))
                c.roundRect(CGRect(x: -0.9, y: -0.5, width: 1.8, height: 1), radius: 0.5, fill: NSColor(hex: "#ffd1e3", alpha: 0.85)); c.cg.restoreGState()
            }
            c.gradient(CGRect(x: 0, y: 0, width: w, height: ground), [NSColor(hex: "#a8643a"), NSColor(hex: "#6b3a1e")])
            var x: CGFloat = 0
            while x < w { c.fill(CGRect(x: x, y: 0, width: 0.5, height: ground), NSColor(hex: "#4a2410", alpha: 0.6)); x += 18 }
            c.fill(CGRect(x: 0, y: ground - 0.6, width: w, height: 0.6), NSColor(hex: "#ffcf9a", alpha: 0.7))
        case 2: // Molten core
            c.gradient(c.bounds, [NSColor(hex: "#3a0c08"), NSColor(hex: "#120406")].reversed())
            Glow.radial(c, CGPoint(x: w * 0.3, y: -6), 120, NSColor(hex: "#ff4a12"), alpha: 0.35)
            Glow.radial(c, CGPoint(x: w * 0.75, y: -6), 120, NSColor(hex: "#ff7a12"), alpha: 0.3)
            var gx: CGFloat = 20
            var i = 0
            while gx < w { // girders / pipes
                let h: CGFloat = 14 + CGFloat((i * 53) % 12)
                c.fill(CGRect(x: gx, y: 0, width: 7, height: h), NSColor(hex: "#24100e"))
                for k in stride(from: CGFloat(2), to: h, by: 4) {
                    c.line(from: CGPoint(x: gx, y: k), to: CGPoint(x: gx + 7, y: k + 3), NSColor(hex: "#3a1a14"), width: 0.6)
                }
                c.fill(CGRect(x: gx + 2.5, y: h - 2, width: 2, height: 1), NSColor(hex: "#ff7a2a", alpha: 0.6 + 0.3 * CGFloat(sin(t * 3 + Double(i)))))
                gx += 62; i += 1
            }
            c.fill(CGRect(x: 0, y: 26, width: w, height: 1.5), NSColor(hex: "#2a1210"))
            for k in 0..<36 { // embers
                let ex = (CGFloat(k) * 61.7 + CGFloat(sin(t + Double(k))) * 6).truncatingRemainder(dividingBy: w)
                let ey = (CGFloat(k) * 5.3 + CGFloat(t) * (6 + CGFloat(k % 5))).truncatingRemainder(dividingBy: 30)
                Glow.radial(c, CGPoint(x: ex, y: ey), 1.6, NSColor(hex: "#ffa040"), alpha: 0.8 * (1 - ey / 30))
            }
            c.gradient(CGRect(x: 0, y: 0, width: w, height: ground), [NSColor(hex: "#4a4040"), NSColor(hex: "#1e1818")])
            var x: CGFloat = 0
            while x < w { c.polygon([CGPoint(x: x, y: ground - 0.9), CGPoint(x: x + 3, y: ground - 0.9), CGPoint(x: x + 5, y: ground), CGPoint(x: x + 2, y: ground)], NSColor(hex: "#ffc21a", alpha: 0.85)); x += 8 }
        default: // Neon city
            c.gradient(c.bounds, [NSColor(hex: "#3a1060"), NSColor(hex: "#0b0420")].reversed())
            Glow.radial(c, CGPoint(x: w * 0.5, y: 4), 160, NSColor(hex: "#ff2bd6"), alpha: 0.18)
            for layer in 0..<2 {
                var bx: CGFloat = CGFloat(layer) * -14 - CGFloat(t) * CGFloat(layer + 1) * 1.5
                var i = layer * 7
                let col = layer == 0 ? NSColor(hex: "#2a1150") : NSColor(hex: "#170a33")
                while bx < w {
                    let bw: CGFloat = 18 + CGFloat((i * 13) % 14)
                    let h: CGFloat = (layer == 0 ? 14 : 8) + CGFloat((i * 29) % (layer == 0 ? 12 : 9))
                    c.fill(CGRect(x: bx, y: 0, width: bw, height: h), col)
                    if layer == 1 || i % 2 == 0 {
                        var wy: CGFloat = 4
                        while wy < h - 2 {
                            var wx = bx + 2
                            while wx < bx + bw - 2 {
                                if ((Int(wx) &* 7 &+ Int(wy) &* 13 &+ i) % 5) < 2 {
                                    c.fill(CGRect(x: wx, y: wy, width: 1.2, height: 1), NSColor(hex: layer == 0 ? "#ff8ae8" : "#7df9ff", alpha: 0.35))
                                }
                                wx += 3
                            }
                            wy += 3
                        }
                    }
                    if layer == 0, i % 5 == 2 { // neon sign
                        let sc = i % 2 == 0 ? NSColor(hex: "#21e6ff") : NSColor(hex: "#ff2bd6")
                        let flick: CGFloat = Int(t * 7 + Double(i)) % 23 == 0 ? 0.2 : 1
                        let r = CGRect(x: bx + 3, y: h - 6, width: bw - 6, height: 2)
                        Glow.capsule(c, r, sc, intensity: 0.4 * flick)
                        c.roundRect(r, radius: 1, fill: sc.withAlphaComponent(0.9 * flick))
                    }
                    bx += bw + 3; i += 1
                }
            }
            c.gradient(CGRect(x: 0, y: 0, width: w, height: ground), [NSColor(hex: "#1a0b33"), NSColor(hex: "#07021a")])
            c.fill(CGRect(x: 0, y: ground - 0.6, width: w, height: 0.6), NSColor(hex: "#21e6ff", alpha: 0.85))
            Glow.capsule(c, CGRect(x: 0, y: ground - 0.6, width: w, height: 0.6), NSColor(hex: "#21e6ff"), halo: 2, intensity: 0.25)
            var x: CGFloat = -CGFloat(t * 8).truncatingRemainder(dividingBy: 24)
            while x < w { c.fill(CGRect(x: x, y: 0, width: 0.5, height: ground - 0.6), NSColor(hex: "#21e6ff", alpha: 0.18)); x += 24 }
        }
        if dim { c.fill(c.bounds, NSColor(white: 0, alpha: 0.45)) }
    }

    private func pagoda(_ c: Canvas, x: CGFloat, color: NSColor) {
        for k in 0..<3 {
            let y = 3 + CGFloat(k) * 5.5, hw = 16 - CGFloat(k) * 4
            c.fill(CGRect(x: x - hw * 0.55, y: y, width: hw * 1.1, height: 4), color)
            c.polygon([CGPoint(x: x - hw - 2, y: y + 4), CGPoint(x: x + hw + 2, y: y + 4), CGPoint(x: x + hw * 0.6, y: y + 6), CGPoint(x: x - hw * 0.6, y: y + 6)], color)
        }
        c.fill(CGRect(x: x - 0.4, y: 20, width: 0.8, height: 4), color)
    }

    private func drawPlatform(_ c: Canvas, _ pl: CGRect) {
        switch arena {
        case 1:
            c.fill(CGRect(x: pl.minX + 6, y: pl.minY - 3, width: 1.2, height: 3), NSColor(hex: "#5a2a14", alpha: 0.8))
            c.fill(CGRect(x: pl.maxX - 7, y: pl.minY - 3, width: 1.2, height: 3), NSColor(hex: "#5a2a14", alpha: 0.8))
            c.roundRect(pl.offsetBy(dx: 0, dy: -0.5), radius: 0.6, fill: NSColor(hex: "#4a2410"))
            c.gradient(pl, [NSColor(hex: "#d4884a"), NSColor(hex: "#8a4a22")], radius: 0.6)
            c.fill(CGRect(x: pl.minX - 2, y: pl.maxY - 0.6, width: pl.width + 4, height: 0.9), NSColor(hex: "#c0392b"))
        case 2:
            Glow.capsule(c, pl, NSColor(hex: "#ff6a1a"), halo: 2, intensity: 0.2)
            c.gradient(pl, [NSColor(hex: "#7a7070"), NSColor(hex: "#3a3232")])
            var x = pl.minX
            while x < pl.maxX - 2 { c.polygon([CGPoint(x: x, y: pl.maxY - 0.5), CGPoint(x: x + 2, y: pl.maxY - 0.5), CGPoint(x: x + 3, y: pl.maxY), CGPoint(x: x + 1, y: pl.maxY)], NSColor(hex: "#ffc21a")); x += 5 }
        default:
            c.gradient(CGRect(x: pl.minX, y: pl.minY - 4, width: pl.width, height: 4), [NSColor(hex: "#ff2bd6", alpha: 0.0), NSColor(hex: "#ff2bd6", alpha: 0.22)])
            Glow.capsule(c, pl, NSColor(hex: "#ff2bd6"), halo: 2.5, intensity: 0.35)
            c.roundRect(pl, radius: pl.height / 2, fill: NSColor(hex: "#ff6be3"))
            c.fill(CGRect(x: pl.minX + 2, y: pl.maxY - 0.6, width: pl.width - 4, height: 0.4), NSColor(white: 1, alpha: 0.8))
        }
    }

    // MARK: fighters

    private func supportY(_ fi: Fighter) -> CGFloat {
        var best = ground
        for pl in platforms where fi.x > pl.minX && fi.x < pl.maxX && pl.maxY <= fi.y + 0.1 { best = max(best, pl.maxY) }
        return best
    }

    private func drawShadow(_ c: Canvas, _ fi: Fighter) {
        let sy = supportY(fi)
        let k = max(0.3, 1 - (fi.y - sy) / 14)
        c.cg.setFillColor(NSColor(white: 0, alpha: 0.35 * k).cgColor)
        c.cg.fillEllipse(in: CGRect(x: fi.x - 6.5 * k, y: sy - 0.8, width: 13 * k, height: 1.6))
    }

    private func limb(_ c: Canvas, _ pts: [CGPoint], _ w: CGFloat, _ col: NSColor) {
        guard let first = pts.first else { return }
        c.cg.setStrokeColor(col.cgColor); c.cg.setLineWidth(w); c.cg.setLineCap(.round); c.cg.setLineJoin(.round)
        c.cg.beginPath(); c.cg.move(to: first); for p in pts.dropFirst() { c.cg.addLine(to: p) }; c.cg.strokePath()
    }

    /// Vector fighter drawn in local space (origin = feet, +x = facing). Poses: idle, walk, jump, fall, hurt, block, shoot, KO.
    private func drawFighter(_ c: Canvas, _ fi: Fighter, label: String, labelColor: NSColor = .white, ghost: CGFloat = 0, scale: CGFloat = 1, time: Double? = nil) {
        let tm = time ?? t
        let cl = Self.classes[fi.cls]
        if ghost == 0, fi.invuln > 0, fi.hp > 0, Int(tm * 30) % 2 == 0 { return }
        let white = fi.flash > 0 || ghost > 0
        func tint(_ col: NSColor) -> NSColor {
            if ghost > 0 { return cl.color.withAlphaComponent(0.45 * ghost) }
            return white ? .white : col
        }
        let dead = fi.hp <= 0 && ghost == 0
        let hurt = tm - fi.hurtT < 0.22 && !dead
        let walking = abs(fi.vx) > 12 && fi.onGround
        let airborne = !fi.onGround
        let ph = tm * (fi.cls == 2 ? 16 : 12)
        let land = max(0, 1 - (tm - fi.landT) / 0.15)
        var lean: CGFloat = fi.cls == 2 ? 0.9 : 0.3
        if walking { lean += 0.5 }
        if hurt { lean = -1.6 }
        if fi.blocking { lean = -0.4 }
        let squash: CGFloat = 1 - CGFloat(land) * 0.12 + (airborne && fi.vy > 40 ? 0.06 : 0)
        let bob: CGFloat = walking ? CGFloat(abs(sin(ph))) * 0.6 : CGFloat(sin(tm * 3.5)) * 0.25
        let recoil: CGFloat = fi.muzzle > 0 ? 1.2 : 0
        let tank = fi.cls == 1, ninja = fi.cls == 2
        let hipY: CGFloat = (tank ? 4.6 : 5) * squash + bob
        let neckY: CGFloat = hipY + (tank ? 5.2 : 5.4) * squash
        let legW: CGFloat = tank ? 2.4 : 1.7
        var fFoot = CGPoint(x: 1.4, y: 0), bFoot = CGPoint(x: -1.4, y: 0)
        if walking {
            fFoot = CGPoint(x: CGFloat(sin(ph)) * 2.6, y: max(0, CGFloat(cos(ph))) * 1.4)
            bFoot = CGPoint(x: -CGFloat(sin(ph)) * 2.6, y: max(0, -CGFloat(cos(ph))) * 1.4)
        } else if airborne {
            fFoot = CGPoint(x: 2.2, y: hipY - 2.2); bFoot = CGPoint(x: -1.6, y: hipY - 3.2)
        } else if fi.blocking { fFoot = CGPoint(x: 2.6, y: 0); bFoot = CGPoint(x: -2.4, y: 0) }

        c.cg.saveGState()
        c.cg.translateBy(x: fi.x, y: fi.y)
        c.cg.scaleBy(x: scale * 1.25 * fi.facing, y: scale * 1.25)
        if dead {
            let k = CGFloat(min(1, (tm - koT) / 0.5))
            c.cg.rotate(by: k * 1.45)
        }
        let body = tint(cl.color), dark = tint(cl.dark)
        let backCol = tint(cl.color.blended(withFraction: 0.45, of: .black) ?? cl.color)
        let hip = CGPoint(x: 0, y: hipY), neck = CGPoint(x: lean, y: neckY)
        func knee(_ foot: CGPoint) -> CGPoint { CGPoint(x: (foot.x + hip.x) / 2 + 0.9, y: (foot.y + hip.y) / 2 + 0.3) }
        let shoulder = CGPoint(x: lean * 0.9, y: neckY - 1)
        let hand = hurt ? CGPoint(x: shoulder.x - 1.5, y: shoulder.y + 2.4) : fi.blocking ? CGPoint(x: shoulder.x + 2.4, y: shoulder.y + 1.5) : CGPoint(x: shoulder.x + 3.6 - recoil, y: shoulder.y - 0.4)

        // back limbs
        limb(c, [hip, knee(bFoot), bFoot], legW, backCol)
        if ninja, ghost == 0 { // headband ribbon trails behind
            let rb = CGPoint(x: neck.x - 1.4, y: neckY + 2.6)
            var pts = [rb]
            for k in 1...4 { pts.append(CGPoint(x: rb.x - CGFloat(k) * 1.6, y: rb.y + CGFloat(sin(tm * 12 - Double(k))) * 0.7 - CGFloat(k) * 0.2)) }
            limb(c, pts, 0.7, tint(cl.color))
            limb(c, [CGPoint(x: neck.x - 1.6, y: neckY + 1.2), CGPoint(x: neck.x - 2.6, y: neckY + 3.6)], 0.6, tint(NSColor(white: 0.8, alpha: 1)))
        }
        if fi.cls == 0 { c.roundRect(CGRect(x: neck.x - 3.6, y: hipY + 1.4, width: 2.2, height: 3.4), radius: 0.5, fill: dark) }
        // torso
        let torsoW: CGFloat = tank ? 5.6 : ninja ? 3.2 : 3.6
        c.cg.saveGState()
        c.cg.translateBy(x: 0, y: hipY)
        c.cg.concatenate(CGAffineTransform(a: 1, b: 0, c: lean / (neckY - hipY), d: 1, tx: 0, ty: 0))
        let tr = CGRect(x: -torsoW / 2, y: -0.3, width: torsoW, height: neckY - hipY + 0.3)
        c.roundRect(tr, radius: tank ? 1.6 : 1.2, fill: ninja ? dark : body)
        c.roundRect(CGRect(x: tr.minX, y: tr.minY, width: tr.width * 0.4, height: tr.height), radius: 1, fill: NSColor(white: 0, alpha: ghost > 0 ? 0 : 0.22))
        if ninja { c.fill(CGRect(x: tr.minX, y: tr.minY + 1.2, width: tr.width, height: 0.7), body) }
        if fi.cls == 0 { c.fill(CGRect(x: tr.minX + 0.5, y: tr.midY, width: tr.width - 1, height: 0.6), tint(NSColor(white: 1, alpha: 0.7))) }
        if tank { c.fill(CGRect(x: tr.minX + 0.6, y: tr.minY + 1.2, width: tr.width - 1.2, height: 0.8), dark) }
        c.cg.restoreGState()
        // front leg
        limb(c, [hip, knee(fFoot), fFoot], legW, ninja ? dark : body)
        c.roundRect(CGRect(x: fFoot.x - 0.6, y: fFoot.y - 0.5, width: legW + 1.2, height: 1.2), radius: 0.5, fill: dark)
        // head
        let head = CGPoint(x: neck.x + 0.4, y: neckY + (tank ? 1.7 : 2.1))
        let hr: CGFloat = tank ? 1.9 : 2.1
        c.circle(center: head, radius: hr, ninja ? dark : body)
        switch fi.cls {
        case 0: // helmet visor
            c.roundRect(CGRect(x: head.x - 0.2, y: head.y - 0.5, width: hr + 0.4, height: 1.3), radius: 0.6, fill: tint(NSColor(hex: "#08202a")))
            c.fill(CGRect(x: head.x + 0.4, y: head.y + 0.1, width: hr - 0.5, height: 0.35), tint(NSColor(hex: "#9ff3ff")))
            limb(c, [CGPoint(x: head.x - 0.8, y: head.y + hr - 0.3), CGPoint(x: head.x - 1.6, y: head.y + hr + 1.4)], 0.4, tint(NSColor(white: 0.85, alpha: 1)))
        case 1: // armored helm with slit + shoulder pad
            c.roundRect(CGRect(x: head.x - hr, y: head.y + 0.3, width: hr * 2, height: hr * 0.8), radius: 0.8, fill: dark)
            c.fill(CGRect(x: head.x, y: head.y - 0.2, width: hr, height: 0.5), tint(NSColor(hex: "#ffe066")))
        default: // mask + headband + eyes
            c.fill(CGRect(x: head.x - hr, y: head.y + 0.4, width: hr * 2, height: 0.8), body)
            c.fill(CGRect(x: head.x + 0.2, y: head.y - 0.5, width: hr - 0.3, height: 0.6), tint(.white))
        }
        // front arm + weapon
        if tank { c.circle(center: CGPoint(x: shoulder.x + 0.2, y: shoulder.y + 0.2), radius: 1.9, dark) }
        limb(c, [shoulder, CGPoint(x: (shoulder.x + hand.x) / 2 + 0.3, y: (shoulder.y + hand.y) / 2 - 0.6), hand], tank ? 1.9 : 1.3, ninja ? dark : body)
        if !hurt && !fi.blocking && !dead {
            switch fi.cls {
            case 0:
                c.roundRect(CGRect(x: hand.x - 1, y: hand.y - 0.4, width: 5.6, height: 1.3), radius: 0.4, fill: tint(NSColor(white: 0.85, alpha: 1)))
                c.fill(CGRect(x: hand.x + 4.2, y: hand.y - 0.1, width: 0.9, height: 0.7), tint(cl.color))
            case 1:
                c.roundRect(CGRect(x: hand.x - 1.4, y: hand.y - 1.2, width: 6.4, height: 2.5), radius: 0.8, fill: tint(NSColor(hex: "#5a5f6a")))
                c.fill(CGRect(x: hand.x - 1, y: hand.y + 0.4, width: 5.6, height: 0.5), tint(NSColor(white: 1, alpha: 0.35)))
                c.fill(CGRect(x: hand.x + 4.4, y: hand.y - 1.0, width: 0.8, height: 2.1), tint(cl.color))
            default:
                Icons.star(c, CGPoint(x: hand.x + 0.9, y: hand.y), 1.3, tint(NSColor(white: 0.85, alpha: 1)), points: 4, inner: 0.35, rotation: CGFloat(tm * 10))
            }
            if fi.muzzle > 0, ghost == 0 {
                let mx = hand.x + (fi.cls == 1 ? 6 : 5.4)
                Glow.radial(c, CGPoint(x: mx, y: hand.y), 5, cl.color, alpha: 0.9)
                Icons.star(c, CGPoint(x: mx + 1, y: hand.y), fi.cls == 1 ? 3.4 : 2.4, .white, points: 4, inner: 0.3, rotation: CGFloat(tm * 40))
            }
        }
        if ninja, ghost == 0 { limb(c, [CGPoint(x: neck.x - 2.2, y: hipY + 0.6), CGPoint(x: neck.x + 1.6, y: neckY + 0.4)], 0.6, tint(NSColor(white: 0.75, alpha: 1))) }
        c.cg.restoreGState()
        if fi.blocking {
            let center = CGPoint(x: fi.x, y: fi.y + 8.5 * scale)
            Glow.radial(c, center, 11, Pal.cyan, alpha: 0.25 + 0.1 * CGFloat(sin(tm * 20)))
            c.cg.setStrokeColor(Pal.cyan.withAlphaComponent(0.85).cgColor); c.cg.setLineWidth(0.7)
            c.cg.addArc(center: center, radius: 10.5, startAngle: fi.facing > 0 ? -1.2 : .pi - 1.2, endAngle: fi.facing > 0 ? 1.2 : .pi + 1.2, clockwise: false); c.cg.strokePath()
        }
        if !label.isEmpty, fi.y < 11, !dead {
            let ty = fi.y + 19
            c.polygon([CGPoint(x: fi.x - 1.4, y: ty), CGPoint(x: fi.x + 1.4, y: ty), CGPoint(x: fi.x, y: ty - 1.4)], labelColor.withAlphaComponent(0.85))
            c.text(label, x: fi.x, y: ty + 0.2, size: 4.8, color: labelColor, weight: .black, align: .center)
        }
    }

    private func drawBullet(_ c: Canvas, _ b: Bullet) {
        if b.ground {
            let h = 4 + CGFloat(sin(t * 40 + Double(b.x))) * 1.2
            Glow.radial(c, CGPoint(x: b.x, y: ground + 1), 8, b.color, alpha: 0.6)
            c.polygon([CGPoint(x: b.x - 6, y: ground), CGPoint(x: b.x - 2, y: ground + h), CGPoint(x: b.x, y: ground + h * 0.6), CGPoint(x: b.x + 2.5, y: ground + h * 1.1), CGPoint(x: b.x + 6, y: ground)], b.color)
            return
        }
        let dir: CGFloat = b.vx > 0 ? 1 : -1
        switch b.kind {
        case 1:
            Glow.radial(c, CGPoint(x: b.x, y: b.y), b.size * 3, b.color, alpha: 0.6)
            c.circle(center: CGPoint(x: b.x, y: b.y), radius: b.size, NSColor(hex: "#ffd09a"))
            c.circle(center: CGPoint(x: b.x + dir * 0.5, y: b.y + 0.4), radius: b.size * 0.45, .white)
        case 2 where !b.special:
            Glow.radial(c, CGPoint(x: b.x, y: b.y), 4, b.color, alpha: 0.5)
            Icons.star(c, CGPoint(x: b.x, y: b.y), b.size + 0.6, NSColor(white: 0.9, alpha: 1), points: 4, inner: 0.35, rotation: CGFloat(t * 25))
            c.circle(center: CGPoint(x: b.x, y: b.y), radius: 0.5, b.color)
        default:
            let len: CGFloat = b.special ? 9 : 7
            let r = CGRect(x: dir > 0 ? b.x - len : b.x, y: b.y - b.size / 2, width: len, height: b.size)
            Glow.capsule(c, r, b.special ? Pal.cyan : b.color, halo: 2, intensity: 0.55)
            c.roundRect(r, radius: b.size / 2, fill: b.special ? .white : (b.color.blended(withFraction: 0.6, of: .white) ?? b.color))
        }
    }

    // MARK: HUD

    private func drawHUD(_ c: Canvas) {
        guard f.count == 2 else { return }
        let barW: CGFloat = min(190, (arenaMax - arenaMin) / 2 - 70)
        let badge = CGRect(x: mid - 18, y: 20.5, width: 36, height: 9)
        for p in 0..<2 {
            let fi = f[p], cl = Self.classes[fi.cls]
            let frac = max(0, fi.hp / cl.hp), chip = max(0, fi.chip / cl.hp)
            let x0 = p == 0 ? badge.minX - 4 - barW : badge.maxX + 4
            let y0: CGFloat = 24.5, h: CGFloat = 4
            func slant(_ a: CGFloat, _ b: CGFloat) -> [CGPoint] { // a…b fractions from the outer end
                let s: CGFloat = 2.5
                if p == 0 {
                    let l = x0 + barW * (1 - b), r = x0 + barW * (1 - a)
                    return [CGPoint(x: l + s, y: y0), CGPoint(x: r, y: y0), CGPoint(x: r - s, y: y0 + h), CGPoint(x: l, y: y0 + h)].map { CGPoint(x: $0.x, y: $0.y) }
                }
                let l = x0 + barW * a, r = x0 + barW * b
                return [CGPoint(x: l, y: y0), CGPoint(x: r - s, y: y0), CGPoint(x: r, y: y0 + h), CGPoint(x: l + s, y: y0 + h)]
            }
            c.polygon(slant(0, 1).map { CGPoint(x: $0.x, y: $0.y - 0.8) }, NSColor(white: 0, alpha: 0.5))
            c.polygon(slant(0, 1), NSColor(hex: "#1a1424", alpha: 0.9))
            if chip > frac { c.polygon(slant(1 - chip, 1), NSColor(hex: "#ff3b3b")) }
            if frac > 0 {
                let col = frac < 0.3 ? (Int(t * 6) % 2 == 0 ? NSColor(hex: "#ff4d4d") : NSColor(hex: "#ffb0b0")) : cl.color
                c.polygon(slant(1 - frac, 1), col)
                c.polygon(slant(1 - frac, 1).map { CGPoint(x: $0.x, y: $0.y > y0 + 1 ? $0.y : y0 + h * 0.55) }, NSColor(white: 1, alpha: 0.25))
            }
            c.cg.setStrokeColor(NSColor(white: 1, alpha: 0.5).cgColor); c.cg.setLineWidth(0.5)
            let outline = slant(0, 1); c.cg.beginPath(); c.cg.addLines(between: outline); c.cg.closePath(); c.cg.strokePath()
            // energy: 4 segments
            let segW = (barW * 0.5 - 3) / 4
            for k in 0..<4 {
                let fill = max(0, min(1, fi.energy / 25 - CGFloat(k)))
                let sx = p == 0 ? x0 + barW - 2 - CGFloat(k + 1) * (segW + 1) : x0 + 2 + CGFloat(k) * (segW + 1)
                let r = CGRect(x: sx, y: 21.2, width: segW, height: 1.8)
                c.roundRect(r, radius: 0.6, fill: NSColor(white: 1, alpha: 0.12))
                let full = fi.energy >= 100
                let ecol = full ? (Int(t * 8) % 2 == 0 ? NSColor(hex: "#ffd23f") : .white) : NSColor(hex: "#ffd23f", alpha: 0.85)
                let fr = p == 0 ? CGRect(x: r.maxX - r.width * fill, y: r.minY, width: r.width * fill, height: r.height) : CGRect(x: r.minX, y: r.minY, width: r.width * fill, height: r.height)
                if fill > 0 { c.roundRect(fr, radius: 0.6, fill: ecol) }
            }
            let tag = "\(name(p)) · \(cl.name)"
            let tagW = Canvas.measure(tag, size: 4.6, weight: .black)
            c.text(tag, x: p == 0 ? x0 + 1 : x0 + barW - 1, y: 19.8, size: 4.6, color: cl.color, weight: .black, align: p == 0 ? .left : .right)
            if fi.energy >= 100 {
                let ex = p == 0 ? x0 + 1 + tagW + 4 : x0 + barW - 1 - tagW - 4
                c.text("★ READY", x: ex, y: 19.8, size: 4.6, color: NSColor(hex: "#ffd23f"), weight: .black, align: p == 0 ? .left : .right)
            }
            for w in 0..<2 {
                let cx = p == 0 ? badge.minX + 5 + CGFloat(w) * 4.5 : badge.maxX - 5 - CGFloat(w) * 4.5
                let won = w < fi.wins
                if won { Glow.radial(c, CGPoint(x: cx, y: badge.minY + 2.6), 3, NSColor(hex: "#ffd23f"), alpha: 0.6) }
                Icons.star(c, CGPoint(x: cx, y: badge.minY + 2.6), 1.9, won ? NSColor(hex: "#ffd23f") : NSColor(white: 1, alpha: 0.2))
            }
        }
        c.roundRect(badge, radius: 2.5, fill: NSColor(hex: "#0b0716", alpha: 0.85), stroke: NSColor(white: 1, alpha: 0.35), lineWidth: 0.5)
        c.text("R\(round)", x: badge.midX, y: badge.minY + 3.6, size: 5.2, color: .white, weight: .black, align: .center)
    }

    private func drawAnnouncer(_ c: Canvas) {
        let cx = mid
        func band(_ alpha: CGFloat, _ accent: NSColor) {
            c.gradient(CGRect(x: arenaMin, y: 6, width: arenaMax - arenaMin, height: 13),
                       [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: 0.55 * alpha), NSColor(white: 0, alpha: 0)], horizontal: true)
            c.fill(CGRect(x: cx - 160 * alpha, y: 6, width: 320 * alpha, height: 0.5), accent.withAlphaComponent(alpha))
            c.fill(CGRect(x: cx - 160 * alpha, y: 18.5, width: 320 * alpha, height: 0.5), accent.withAlphaComponent(alpha))
        }
        func big(_ s: String, _ age: Double, _ col: NSColor, size: CGFloat = 13) {
            let k = CGFloat(Ease.outBack(age / 0.3, 2.5))
            let sc = 0.4 + 0.6 * k
            c.cg.saveGState(); c.cg.translateBy(x: cx, y: 12.3); c.cg.scaleBy(x: sc, y: sc)
            Arcade.display(c, s, x: 0, y: -size * 0.42, size: size, color: col, align: .center)
            c.cg.restoreGState()
        }
        switch phase {
        case .countdown:
            let age = 2.4 - timer
            band(CGFloat(Ease.outCubic(age / 0.3)), NSColor(hex: "#ffd23f"))
            if timer > 1.0 { big("ROUND \(round)", age, .white) } else { big("READY…", 1.4 - timer, NSColor(hex: "#ffd23f")) }
        case .fight where t - fightT < 0.8:
            let age = t - fightT
            band(CGFloat(1 - Ease.inCubic((age - 0.5) / 0.3)), NSColor(hex: "#ff4d4d"))
            big("FIGHT!", age, NSColor(hex: "#ff4d4d"), size: 16)
        case .roundOver:
            let age = t - koT
            if age < 1.2 {
                band(1, NSColor(hex: "#ff4d4d"))
                big("K.O.", age, NSColor(hex: "#ffd23f"), size: 18)
            } else {
                let w = lastWinner, col = Self.classes[f[w].cls].color
                band(1, col)
                big("\(name(w)) TAKES ROUND \(round)", age - 1.2, col, size: 11)
            }
        case .matchOver:
            let w = lastWinner, cl = Self.classes[f[w].cls]
            let age = t - phaseT
            Arcade.panel(c, CGRect(x: cx - 170, y: 2, width: 340, height: 26), accent: cl.color)
            var champ = Fighter(cls: f[w].cls, x: cx - 145); champ.facing = 1
            drawFighter(c, champ, label: "", scale: 1.2)
            Icons.star(c, CGPoint(x: cx - 145, y: 26), 2.2 + CGFloat(sin(age * 5)) * 0.3, NSColor(hex: "#ffd23f"))
            big("\(name(w)) WINS!", age, cl.color, size: 13)
            c.text("\(f[0].wins) – \(f[1].wins)  ·  \(cl.name)", x: cx, y: 3.5, size: 6, color: NSColor(white: 0.8, alpha: 1), weight: .bold, align: .center)
            if timer <= 0 { c.text("F / TAP ▸ REMATCH", x: cx + 160, y: 11, size: 6, color: NSColor(white: 1, alpha: CGFloat(0.55 + 0.45 * sin(age * 5))), weight: .heavy, align: .right) }
        default: break
        }
    }

    // MARK: menus

    private func drawSetup(_ c: Canvas) {
        let age = t - phaseT
        let x0 = arenaMin + 6
        Arcade.display(c, "STRIP", x: x0, y: 15.5, size: 10, color: Pal.cyan)
        Arcade.display(c, "DUEL", x: x0 + 2, y: 2.5, size: 13, color: Pal.magenta)
        var x = x0 + 64
        setupRects = []
        let items = ["VS BOT", "VS FRIEND", "◀ " + Self.arenas[arena].name + " ▶", "FIGHT ▶"]
        for (i, label) in items.enumerated() {
            let lw = Canvas.measure(label, size: 8, weight: .heavy) + 20
            let w: CGFloat = max(i == 3 ? 86 : 70, lw)
            let k = CGFloat(Ease.outBack((age - Double(i) * 0.06) / 0.4, 1.6))
            let r = CGRect(x: x, y: 4 - (1 - k) * 24, width: w, height: 22)
            let sel = (i == 0 && vsBot) || (i == 1 && !vsBot)
            let accent = i == 3 ? Pal.magenta : i == 2 ? Self.arenas[arena].accent : Pal.cyan
            if focus == i { Glow.radial(c, CGPoint(x: r.midX, y: r.midY), w * 0.6, accent, alpha: 0.35 + 0.15 * CGFloat(sin(age * 5))) }
            if i == 3 || sel {
                c.gradient(r, [accent.blended(withFraction: 0.25, of: .white) ?? accent, accent], radius: 7)
            } else {
                Arcade.panel(c, r, accent: accent.withAlphaComponent(0.6), radius: 7)
            }
            if focus == i { c.roundRect(r.insetBy(dx: -1.2, dy: -1.2), radius: 8, fill: .clear, stroke: .white, lineWidth: 1) }
            if i == 2 { c.text("ARENA", x: r.midX, y: r.maxY - 6.5, size: 4.6, color: accent, weight: .black, align: .center) }
            c.text(label, x: r.midX, y: i == 2 ? r.minY + 4 : r.midY - 5, size: 8, color: sel || i == 3 ? Arcade.ink : .white, weight: .heavy, align: .center)
            setupRects.append(r)
            x += w + 6
        }
        // roster parade
        let rx = x + 18
        for k in 0..<3 {
            var fi = Fighter(cls: k, x: rx + CGFloat(k) * 30)
            fi.facing = 1
            fi.y = 3
            drawFighter(c, fi, label: "", scale: 1.05)
        }
        let hx = rx + 100
        Arcade.hints(c, [("WASD", "P1"), ("F", "shoot"), ("G", "★")], x: hx, y: 16)
        Arcade.hints(c, [("← → ↑", "P2"), ("/", "shoot"), (".", "★")], x: hx, y: 4)
    }

    private func drawPick(_ c: Canvas) {
        let age = t - phaseT
        for p in 0..<2 {
            let cl = Self.classes[picks[p]]
            let h0 = p == 0 ? arenaMin : mid + 18, h1 = p == 0 ? mid - 18 : arenaMax
            let slide = CGFloat(1 - Ease.outCubic(age / 0.4)) * (p == 0 ? -120 : 120)
            c.cg.saveGState()
            c.cg.translateBy(x: slide, y: 0)
            // slanted colour panel
            let s: CGFloat = 10
            let pts = p == 0 ? [CGPoint(x: h0, y: 1), CGPoint(x: h1, y: 1), CGPoint(x: h1 - s, y: 29), CGPoint(x: h0, y: 29)]
                             : [CGPoint(x: h0, y: 1), CGPoint(x: h1, y: 1), CGPoint(x: h1, y: 29), CGPoint(x: h0 - s, y: 29)]
            c.polygon(pts, NSColor(hex: "#0b0716", alpha: 0.88))
            c.clip(CGRect(x: h0 - s, y: 1, width: h1 - h0 + s, height: 28)) {
                c.gradient(CGRect(x: h0, y: 1, width: h1 - h0, height: 28), p == 0 ? [cl.color.withAlphaComponent(0.45), cl.color.withAlphaComponent(0.0)] : [cl.color.withAlphaComponent(0.0), cl.color.withAlphaComponent(0.45)], horizontal: true)
                for k in 0..<14 { // speed lines
                    let lx = (CGFloat(k) * 37 + CGFloat(t) * 60 * (p == 0 ? 1 : -1)).truncatingRemainder(dividingBy: h1 - h0)
                    let ax = (lx < 0 ? lx + h1 - h0 : lx) + h0
                    c.fill(CGRect(x: ax, y: CGFloat((k * 7) % 26) + 2, width: 14, height: 0.4), cl.color.withAlphaComponent(0.25))
                }
            }
            c.cg.setStrokeColor((ready[p] ? NSColor(hex: "#ffd23f") : cl.color).cgColor); c.cg.setLineWidth(ready[p] ? 1.4 : 0.8)
            c.cg.beginPath(); c.cg.addLines(between: pts); c.cg.closePath(); c.cg.strokePath()
            let inner = p == 0 ? h1 - 46 : h0 + 46
            let outer = p == 0 ? h0 + 14 : h1 - 14
            // portrait
            Glow.radial(c, CGPoint(x: inner, y: 12), 22, cl.color, alpha: 0.45)
            var demoF = Fighter(cls: picks[p], x: inner); demoF.y = 1.5; demoF.facing = p == 0 ? 1 : -1
            if ready[p] { demoF.muzzle = Int(t * 3) % 2 == 0 ? 0.05 : 0 }
            drawFighter(c, demoF, label: "", scale: 1.5)
            // name + blurb
            let who = p == 0 ? "P1" : (vsBot ? "CPU" : "P2")
            let align: NSTextAlignment = p == 0 ? .left : .right
            let tx = p == 0 ? outer + 10 : outer - 10
            c.text(who, x: tx, y: 21, size: 5.5, color: p == 0 ? Pal.cyan : Pal.magenta, weight: .black, align: align)
            Arcade.display(c, cl.name, x: tx, y: 9.5, size: 13, color: cl.color, align: align)
            c.text("★ " + cl.special + "  ·  " + cl.blurb, x: tx, y: 2.8, size: 5.6, color: NSColor(white: 0.85, alpha: 1), weight: .semibold, align: align)
            // stats
            let sx = p == 0 ? tx + 92 : tx - 92 - 60
            for (k, lbl) in ["HP", "SPD", "PWR"].enumerated() {
                let y = 21 - CGFloat(k) * 6.5
                c.text(lbl, x: sx, y: y - 1.5, size: 4.8, color: NSColor(white: 0.7, alpha: 1), weight: .black)
                for seg in 0..<5 {
                    let on = seg < cl.stats[k]
                    c.roundRect(CGRect(x: sx + 14 + CGFloat(seg) * 9, y: y - 1, width: 8, height: 2.6), radius: 0.8, fill: on ? cl.color : NSColor(white: 1, alpha: 0.12))
                }
            }
            // roster chips
            for k in 0..<Self.classes.count {
                let cx = p == 0 ? inner - 30 + CGFloat(k) * 0 : inner + 30
                let cy = 23 - CGFloat(k) * 8
                let selc = k == picks[p]
                c.roundRect(CGRect(x: cx - 4, y: cy - 3, width: 8, height: 6), radius: 1.5, fill: selc ? Self.classes[k].color : NSColor(white: 1, alpha: 0.1),
                            stroke: selc ? .white : nil, lineWidth: 0.6)
                c.text(String(Self.classes[k].name.prefix(1)), x: cx, y: cy - 2.6, size: 4.6, color: selc ? Arcade.ink : NSColor(white: 0.7, alpha: 1), weight: .black, align: .center)
            }
            // arrows
            let ak = CGFloat(sin(t * 6)) * 1
            c.text("◀", x: (p == 0 ? h0 + 5 : h0 - 2) - ak, y: 10, size: 9, color: cl.color, weight: .heavy, align: .center)
            c.text("▶", x: (p == 0 ? h1 - 6 : h1 - 5) + ak, y: 10, size: 9, color: cl.color, weight: .heavy, align: .center)
            if ready[p] {
                c.cg.saveGState(); c.cg.translateBy(x: inner + (p == 0 ? -24 : 24), y: 6); c.cg.rotate(by: -0.18)
                c.roundRect(CGRect(x: -17, y: -4, width: 34, height: 9), radius: 2, fill: NSColor(hex: "#ffd23f"))
                c.text("READY!", x: 0, y: -3.2, size: 7, color: Arcade.ink, weight: .black, align: .center)
                c.cg.restoreGState()
            } else if !(p == 1 && vsBot) {
                c.text(p == 0 ? "F / TAP ▸ READY" : "/ / TAP ▸ READY", x: inner, y: 24.5, size: 4.8,
                       color: NSColor(white: 1, alpha: CGFloat(0.5 + 0.4 * sin(t * 5))), weight: .black, align: .center)
            }
            c.cg.restoreGState()
        }
        // VS badge
        let k = CGFloat(Ease.outBack((age - 0.25) / 0.4, 3))
        if k > 0 {
            c.cg.saveGState(); c.cg.translateBy(x: mid, y: 15); c.cg.scaleBy(x: k, y: k)
            Glow.radial(c, .zero, 20, NSColor(hex: "#ffd23f"), alpha: 0.5)
            Arcade.display(c, "VS", x: 0, y: -7.5, size: 17, color: NSColor(hex: "#ffd23f"), align: .center)
            c.cg.restoreGState()
        }
        c.text(Self.arenas[arena].name, x: mid, y: 1.5, size: 4.6, color: Self.arenas[arena].accent, weight: .black, align: .center)
    }
}
