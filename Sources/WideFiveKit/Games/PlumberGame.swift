import AppKit

/// "Tiny Plumber": a Mario-style side-scroller. ◀ ▶ to walk, B to run, A to jump (hold for higher).
/// Stomp goombas, avoid spikies, bump ? blocks for coins & mushrooms, break bricks when big, grab the flag.
public final class PlumberGame: StripMode, DemoStartable {
    public let id = "plumber"
    public let title = "Tiny Plumber"
    public let icon = "gamecontroller.fill"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    enum State { case title, playing, dying(Double), clear(Double), gameOver }
    struct Enemy { var body: Body; var spiky: Bool; var dir: CGFloat = -1; var squashed: Double? = nil; var dead = false }
    struct PowerUp { var body: Body; var star: Bool; var dir: CGFloat = 1; var rise: CGFloat = 5 }
    struct FloatText { var x: CGFloat, y: CGFloat, text: String, life: Double }

    let world = TileWorld()
    let controls = PadControls()
    let particles = Particles()
    var state: State = .title
    var player = Body(x: 30, y: 5, w: 6, h: 7)
    var big = false
    var facing: CGFloat = 1
    var invuln = 0.0, starTime = 0.0, coyote = 0.0
    var enemies: [Enemy] = []
    var powerUps: [PowerUp] = []
    var coins: [CGPoint] = []
    var contents: [Int: String] = [:]
    var texts: [FloatText] = []
    var camX: CGFloat = 0
    var viewW: CGFloat = 1085
    var level = 1, lives = 3, score = 0, coinCount = 0
    var timeLeft = 300.0
    var flagX: CGFloat = 0
    var animT = 0.0
    var rng = SeededRNG(seed: 1)
    var demo = false
    var stateT = 0.0
    var hitStop = 0.0
    var pulse: CGFloat = 0
    var newBest = false
    var wasGround = true
    var landT = -9.0
    let shake = Shake(maxOffset: 2.4)

    public func startDemo() { demo = true; startGame(); controls.reset() }

    public init() { buildLevel() }

    public func activate(_ ctx: ModeContext) { controls.reset() }

    // MARK: Level generation

    func buildLevel() {
        rng = SeededRNG(seed: UInt64(level) * 7919)
        world.cols = []; world.origin = 0; world.leftWall = true
        enemies = []; powerUps = []; coins = []; contents = [:]; texts = []
        let length = 380 + level * 40
        for _ in 0..<length { var col = world.emptyColumn(); col[0] = .ground; world.append(col) }
        var c = 24
        while c < length - 30 {
            let roll = rng.next(100)
            switch roll {
            case 0..<20: // gap
                let w = 2 + rng.next(min(3, 1 + level))
                for i in 0..<w { world.set(c + i, 0, .empty) }
                for i in -1...w { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: 22)) }
                c += w + 6
            case 20..<45: // brick row with ? blocks and goomba below
                let w = 4 + rng.next(4)
                for i in 0..<w {
                    let q = rng.next(3) == 0
                    world.set(c + i, 3, q ? .question : .brick)
                    if q { contents[(c + i) * 10 + 3] = rng.next(5) == 0 ? (rng.next(4) == 0 ? "star" : "mushroom") : "coin" }
                    if !q, rng.next(3) == 0 { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: 21)) }
                }
                enemies.append(Enemy(body: Body(x: CGFloat(c + w) * 5, y: 5, w: 6, h: 6), spiky: false))
                c += w + 5
            case 45..<60: // pipe
                for r in 1...2 { world.set(c, r, .pipe); world.set(c + 1, r, .pipe) }
                if rng.next(2) == 0 { enemies.append(Enemy(body: Body(x: CGFloat(c + 5) * 5, y: 5, w: 6, h: 6), spiky: level > 1 && rng.next(3) == 0)) }
                c += 8
            case 60..<72: // stairs
                let hgt = 2 + rng.next(2)
                for i in 0..<hgt { for r in 1...(i + 1) { world.set(c + i, r, .block) } }
                for i in 0..<hgt { for r in 1...(hgt - i) { world.set(c + hgt + 2 + i, r, .block) } }
                c += hgt * 2 + 6
            case 72..<88: // enemy squad
                let n = 1 + rng.next(2 + level / 2)
                for i in 0..<n {
                    enemies.append(Enemy(body: Body(x: CGFloat(c + i * 3) * 5, y: 5, w: 6, h: 6), spiky: level > 1 && rng.next(4) == 0))
                }
                c += n * 3 + 6
            default: // coin arc
                for i in 0..<6 { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: 12 + CGFloat([0, 4, 6, 6, 4, 0][i]))) }
                c += 9
            }
        }
        flagX = CGFloat(length - 12) * 5
        for i in (length - 20)..<(length - 14) { for r in 1...min(4, i - (length - 21)) { world.set(i, r, .block) } }
        resetPlayer()
        timeLeft = 300
    }

    func resetPlayer() {
        player = Body(x: 70, y: 5, w: 6, h: big ? 10 : 7)
        camX = 0; invuln = 0; starTime = 0
        controls.reset()
    }

    // MARK: Update

    public func update(dt: Double) {
        animT += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt))
        pulse = max(0, pulse - CGFloat(dt) * 3)
        if hitStop > 0 { hitStop -= dt; return }
        texts = texts.compactMap { var t = $0; t.life -= dt; t.y += CGFloat(dt) * 12; return t.life > 0 ? t : nil }
        switch state {
        case .title, .gameOver:
            if controls.jumpPressed { controls.jumpPressed = false; startGame() }
        case .dying(let t):
            player.vy -= 500 * CGFloat(dt); player.y += player.vy * CGFloat(dt)
            if animT - t > 2 {
                lives -= 1
                if lives <= 0 { newBest = HighScores.submit(id, score); state = .gameOver; stateT = animT; demo = false } else { big = false; buildLevel(); state = .playing }
            }
        case .clear(let t):
            if timeLeft > 0 { let d = min(timeLeft, dt * 120); timeLeft -= d; score += Int(d * 10) }
            player.vx = 40; player.vy -= 600 * CGFloat(dt)
            world.move(&player, dt: CGFloat(dt))
            if animT - t > 3 { level += 1; buildLevel(); state = .playing }
        case .playing:
            step(CGFloat(dt))
        }
    }

    func startGame() { level = 1; lives = 3; score = 0; coinCount = 0; big = false; buildLevel(); state = .playing; stateT = animT }

    func step(_ dt: CGFloat) {
        timeLeft -= Double(dt) * 2
        if timeLeft <= 0 { die(); return }
        invuln = max(0, invuln - Double(dt)); starTime = max(0, starTime - Double(dt))
        if demo { botStep() }
        let run = controls.run
        let accel: CGFloat = run ? 300 : 220, maxV: CGFloat = run ? 115 : 72
        if controls.left { player.vx -= accel * dt; facing = -1 }
        else if controls.right { player.vx += accel * dt; facing = 1 }
        else { player.vx -= min(abs(player.vx), 320 * dt) * (player.vx > 0 ? 1 : -1) }
        player.vx = max(-maxV, min(maxV, player.vx))
        coyote = player.onGround ? 0.08 : coyote - Double(dt)
        if controls.jumpPressed {
            controls.jumpPressed = false
            if coyote > 0 { player.vy = 128 + abs(player.vx) * 0.12; coyote = 0; particles.burst(x: player.midX, y: player.y, count: 4, colors: [.white], speed: 20, life: 0.25, size: 1) }
        }
        let g: CGFloat = (controls.jump && player.vy > 0) ? 300 : 640
        player.vy = max(-220, player.vy - g * dt)
        world.move(&player, dt: dt) { [weak self] c, r in self?.bump(c, r) }
        if player.onGround, !wasGround {
            landT = animT
            particles.burst(x: player.midX, y: player.y, count: 5, colors: [NSColor(white: 1, alpha: 0.8)], speed: 22, life: 0.3, size: 1.2, gravity: 0, kind: .dot, drag: 5, direction: .pi / 2, spread: 2.6)
        }
        if player.onGround, abs(player.vx) > 90, Int(animT * 20) % 3 == 0 {
            particles.burst(x: player.midX - facing * 2, y: player.y, count: 1, colors: [NSColor(white: 1, alpha: 0.6)], speed: 10, life: 0.25, size: 1, gravity: 10, kind: .dot, drag: 3)
        }
        wasGround = player.onGround
        if player.x < camX { player.x = camX; player.vx = max(0, player.vx) }
        if player.y < -12 { die(); return }

        camX = max(camX, min(player.x - viewW * 0.4, world.width - viewW))
        camX = max(0, camX)

        // Coins
        let pr = player.rect
        coins.removeAll { p in
            guard pr.intersects(CGRect(x: p.x, y: p.y, width: 3, height: 5)) else { return false }
            coinCount += 1; score += 200; pulse = 1
            particles.burst(x: p.x + 1.5, y: p.y + 2.5, count: 7, colors: [Pal.yellow, .white], speed: 40, life: 0.35, size: 1.3, gravity: 0, kind: .sparkle, drag: 4)
            if coinCount % 100 == 0 { lives += 1; texts.append(FloatText(x: p.x, y: p.y, text: "1UP", life: 1)) }
            return true
        }

        // Power-ups
        for i in powerUps.indices.reversed() {
            var p = powerUps[i]
            if p.rise > 0 { let d = min(p.rise, 12 * dt); p.body.y += d; p.rise -= d }
            else {
                p.body.vx = p.dir * 30
                p.body.vy -= 500 * dt
                if p.star && p.body.onGround { p.body.vy = 120 }
                world.move(&p.body, dt: dt)
                if p.body.hitWall { p.dir *= -1 }
            }
            if p.body.y < -10 { powerUps.remove(at: i); continue }
            if p.body.rect.intersects(pr) {
                if p.star { starTime = 8; texts.append(FloatText(x: player.x, y: 20, text: "★ STAR", life: 1)) }
                else if !big { big = true; player.h = 10; texts.append(FloatText(x: player.x, y: 20, text: "POWER UP", life: 1)) }
                score += 1000
                powerUps.remove(at: i); continue
            }
            powerUps[i] = p
        }

        // Enemies
        for i in enemies.indices {
            var e = enemies[i]
            if e.dead { continue }
            if let s = e.squashed { if animT - s > 0.5 { e.dead = true }; enemies[i] = e; continue }
            guard e.body.x < camX + viewW + 40, e.body.x > camX - 80 else { continue }
            e.body.vx = e.dir * 22
            e.body.vy = max(-200, e.body.vy - 600 * dt)
            world.move(&e.body, dt: dt)
            if e.body.hitWall { e.dir *= -1 }
            if e.body.y < -10 { e.dead = true }
            if e.body.rect.insetBy(dx: 0.5, dy: 0.5).intersects(pr) {
                if starTime > 0 {
                    e.dead = true; score += 200
                    particles.burst(x: e.body.midX, y: e.body.y + 3, count: 12, colors: [Pal.brown, Pal.yellow, .white], speed: 70, kind: .shard)
                    particles.ring(x: e.body.midX, y: e.body.y + 3, color: Pal.yellow); shake.add(0.2)
                } else if !e.spiky, player.vy < 0, player.y > e.body.y + 2 {
                    e.squashed = animT; player.vy = 110; score += 100; hitStop = 0.05; shake.add(0.22); pulse = 1
                    particles.ring(x: e.body.midX, y: e.body.y + 2, color: .white, radius: 9, life: 0.25)
                    particles.burst(x: e.body.midX, y: e.body.y + 2, count: 6, colors: [.white, Pal.yellow], speed: 40, life: 0.3, size: 1.2, gravity: 0, kind: .sparkle, drag: 4)
                    texts.append(FloatText(x: e.body.x, y: e.body.y + 8, text: "100", life: 0.7))
                } else if invuln <= 0 {
                    hurt()
                }
            }
            enemies[i] = e
        }
        enemies.removeAll { $0.dead && $0.squashed == nil || ($0.squashed.map { animT - $0 > 0.5 } ?? false) }

        if player.x + player.w >= flagX {
            score += Int(max(0, 30 - player.y) * 100)
            texts.append(FloatText(x: flagX, y: 22, text: "COURSE CLEAR!", life: 2.5))
            particles.burst(x: flagX, y: 25, count: 50, colors: [Pal.red, Pal.yellow, Pal.cyan, Pal.magenta, .white], speed: 100, life: 1.4, size: 1.6, gravity: -80, kind: .shard)
            particles.ring(x: flagX, y: 22, color: Pal.yellow, radius: 22, life: 0.6)
            state = .clear(animT)
        }
    }

    func bump(_ c: Int, _ r: Int) {
        let t = world.get(c, r)
        let x = CGFloat(c) * 5, y = CGFloat(r) * 5
        if t == .question {
            world.set(c, r, .used)
            switch contents[c * 10 + r] ?? "coin" {
            case "mushroom": powerUps.append(PowerUp(body: Body(x: x, y: y, w: 5, h: 5), star: false))
            case "star": powerUps.append(PowerUp(body: Body(x: x, y: y, w: 5, h: 5), star: true))
            default:
                coinCount += 1; score += 200
                particles.burst(x: x + 2.5, y: y + 6, count: 8, colors: [Pal.yellow, .white], speed: 50, life: 0.5, size: 1.3, kind: .sparkle)
                pulse = 1
                texts.append(FloatText(x: x, y: y + 6, text: "200", life: 0.6))
            }
        } else if t == .brick {
            if big {
                world.set(c, r, .empty); score += 50
                particles.burst(x: x + 2.5, y: y + 2.5, count: 12, colors: [NSColor(hex: "#b85c1c"), NSColor(hex: "#5a2a0a")], speed: 80, life: 0.8, size: 1.6, gravity: -400)
            } else {
                particles.burst(x: x + 2.5, y: y, count: 3, colors: [.white], speed: 15, life: 0.2, size: 0.8)
            }
        }
        for i in enemies.indices where abs(enemies[i].body.midX - (x + 2.5)) < 5 && abs(enemies[i].body.y - (y + 5)) < 2 {
            enemies[i].dead = true; score += 100
        }
    }

    func hurt() {
        if big { big = false; player.h = 7; invuln = 1.6; shake.add(0.5); hitStop = 0.08; texts.append(FloatText(x: player.x, y: 20, text: "OUCH", life: 0.6)) }
        else { die() }
    }

    func die() {
        guard case .playing = state else { return }
        state = .dying(animT)
        player.vy = 150; shake.add(0.7); hitStop = 0.25
        particles.flash(x: player.midX, y: player.y + 4, color: .white, radius: 14)
        particles.burst(x: player.midX, y: player.y + 4, count: 16, colors: [Pal.red, Pal.blue, Pal.skin], speed: 70, kind: .shard)
    }

    // MARK: Draw

    public func draw(_ c: Canvas) {
        viewW = c.width
        controls.width = c.width
        c.gradient(c.bounds, [NSColor(hex: "#cfeaff"), NSColor(hex: "#5c94fc")])
        let sunP = CGPoint(x: c.width * 0.78 - camX * 0.02, y: 24)
        Glow.radial(c, sunP, 40, NSColor(hex: "#fff3b0"), alpha: 0.55)
        c.circle(center: sunP, radius: 4, NSColor(hex: "#fff8d6"))
        let mOff = (camX * 0.08).truncatingRemainder(dividingBy: 120)
        for i in -1..<Int(c.width / 120) + 2 {
            let mx = CGFloat(i) * 120 - mOff, h = CGFloat(14 + (i &* 7 &+ 3) % 3 * 3)
            c.polygon([CGPoint(x: mx - 40, y: 0), CGPoint(x: mx + 30, y: h), CGPoint(x: mx + 100, y: 0)], NSColor(hex: "#8fb3e8"))
            c.polygon([CGPoint(x: mx + 30, y: h), CGPoint(x: mx + 24, y: h - 3), CGPoint(x: mx + 30, y: h - 2), CGPoint(x: mx + 36, y: h - 3)], .white.withAlphaComponent(0.85))
        }
        for i in 0..<14 {
            let span: CGFloat = 1600
            var cx = (CGFloat(i) * 117 - camX * 0.35 - CGFloat(animT) * 2.5).truncatingRemainder(dividingBy: span)
            if cx < -40 { cx += span }
            let cy = 20 + CGFloat((i * 5) % 4) * 1.6, k = 0.9 + CGFloat(i % 3) * 0.2
            for (dx, dy, r) in [(-4.5, 0.0, 2.6), (0.0, 1.4, 3.6), (4.5, 0.4, 2.8), (2.0, -0.6, 2.6)] as [(CGFloat, CGFloat, CGFloat)] {
                c.circle(center: CGPoint(x: cx + dx * k, y: cy + dy * k - 0.6), radius: r * k, NSColor(hex: "#c4d8f5"))
            }
            for (dx, dy, r) in [(-4.5, 0.0, 2.6), (0.0, 1.4, 3.6), (4.5, 0.4, 2.8)] as [(CGFloat, CGFloat, CGFloat)] {
                c.circle(center: CGPoint(x: cx + dx * k, y: cy + dy * k), radius: r * k, .white)
            }
        }
        let hOff = (camX * 0.3).truncatingRemainder(dividingBy: 90)
        for i in -1..<Int(c.width / 90) + 2 {
            let hx = CGFloat(i) * 90 - hOff + 20, idx = i + Int(camX * 0.3 / 90)
            let r = 11 + CGFloat(abs(idx) % 3) * 3
            c.circle(center: CGPoint(x: hx, y: 1), radius: r, NSColor(hex: "#3f9a45"))
            c.circle(center: CGPoint(x: hx - r * 0.25, y: 1 + r * 0.15), radius: r * 0.8, NSColor(hex: "#56b85a"))
            c.circle(center: CGPoint(x: hx - r * 0.35, y: r * 0.55), radius: 0.8, NSColor(hex: "#2d7a33"))
            c.circle(center: CGPoint(x: hx + r * 0.1, y: r * 0.35), radius: 0.8, NSColor(hex: "#2d7a33"))
        }
        c.cg.saveGState()
        shake.apply(c)
        let T = TileWorld.T
        let c0 = max(0, Int(camX / T) - 1), c1 = Int((camX + c.width) / T) + 1
        for col in c0...c1 { for r in 0..<TileWorld.rows {
            let t = world.get(col, r)
            if t != .empty { TileArt.draw(c, t, x: CGFloat(col) * T - camX, y: CGFloat(r) * T, time: animT) }
        } }
        // Flag + castle
        let fx = flagX - camX
        if fx < c.width + 60 {
            c.fill(CGRect(x: fx, y: 5, width: 1, height: 24), NSColor(hex: "#e0e0e0"))
            c.circle(center: CGPoint(x: fx + 0.5, y: 29), radius: 1.2, Pal.green)
            let wave = CGFloat(sin(animT * 6)) * 0.8
            c.cg.setFillColor(Pal.green.cgColor)
            c.cg.move(to: CGPoint(x: fx, y: 28)); c.cg.addLine(to: CGPoint(x: fx - 8, y: 25.5 + wave)); c.cg.addLine(to: CGPoint(x: fx, y: 23)); c.cg.fillPath()
            let castle = CGRect(x: fx + 25, y: 5, width: 25, height: 13)
            c.gradient(castle, [NSColor(hex: "#d07a3c"), NSColor(hex: "#8a4214")], horizontal: true)
            for row in 0..<4 { c.fill(CGRect(x: castle.minX, y: castle.minY + CGFloat(row) * 3.3, width: castle.width, height: 0.4), NSColor(hex: "#5a2a0a").withAlphaComponent(0.6)) }
            for k in 0..<5 { c.fill(CGRect(x: castle.minX + CGFloat(k) * 5 + 1, y: castle.maxY, width: 3, height: 2.5), NSColor(hex: "#b85c1c")) }
            let tower = CGRect(x: castle.midX - 5, y: castle.maxY, width: 10, height: 7)
            c.gradient(tower, [NSColor(hex: "#d07a3c"), NSColor(hex: "#8a4214")], horizontal: true)
            c.fill(CGRect(x: tower.midX - 0.3, y: tower.maxY, width: 0.6, height: 4), NSColor(hex: "#e0e0e0"))
            c.polygon([CGPoint(x: tower.midX + 0.3, y: tower.maxY + 4), CGPoint(x: tower.midX + 4, y: tower.maxY + 3), CGPoint(x: tower.midX + 0.3, y: tower.maxY + 2)], Pal.red)
            c.roundRect(CGRect(x: tower.midX - 1.2, y: tower.minY + 2, width: 2.4, height: 3), radius: 1.2, fill: NSColor(hex: "#2a1408"))
            c.roundRect(CGRect(x: castle.midX - 3, y: 5, width: 6, height: 8), radius: 3, fill: NSColor(hex: "#1a0a04"))
        }
        for p in coins where p.x > camX - 5 && p.x < camX + c.width {
            let cp = CGPoint(x: p.x - camX + 1.5, y: p.y + 2.5)
            Glow.radial(c, cp, 4, Pal.yellow, alpha: 0.3)
            Icons.coin(c, cp, 2.3, spin: animT * 4 + Double(p.x) * 0.03)
        }
        for p in powerUps { c.sprite(p.star ? Sprites.star : Sprites.mushroom, x: p.body.x - camX, y: p.body.y, tint: p.star && Int(animT * 10) % 2 == 0 ? .white : nil) }
        for e in enemies where !e.dead {
            let x = e.body.x - camX
            guard x > -10, x < c.width + 10 else { continue }
            c.fill(CGRect(x: x + 0.5, y: e.body.y - 0.4, width: 5, height: 0.8), NSColor(white: 0, alpha: 0.18))
            if e.squashed != nil { c.sprite(Sprites.goombaFlat, x: x, y: e.body.y) }
            else if e.spiky { c.sprite(Sprites.spiky, x: x, y: e.body.y, flipX: Int(animT * 4) % 2 == 0) }
            else { c.sprite(Int(animT * 5) % 2 == 0 ? Sprites.goomba1 : Sprites.goomba2, x: x, y: e.body.y) }
        }
        drawPlayer(c)
        particles.draw(c, camX: camX)
        for t in texts {
            let k = CGFloat(min(1, t.life / 0.3))
            _ = Arcade.display(c, t.text, x: t.x - camX, y: t.y, size: 7, color: NSColor(white: 1, alpha: k), align: .center)
        }
        c.cg.restoreGState()

        let showPad = controls.visible && !demo
        if showPad, case .playing = state { controls.draw(c) }
        Arcade.hud(c, [.init("WORLD", "1-\(level)", color: Pal.yellow), .init("COINS", "\(coinCount)", color: Pal.yellow),
                       .init("SCORE", String(format: "%06d", score)), .init("TIME", "\(max(0, Int(timeLeft)))", color: timeLeft < 60 ? Pal.red : .white),
                       .init(lives: lives)],
                   accent: Pal.red, pulse: pulse, right: showPad ? c.width - controls.btnW * 2 - 14 : nil)
        if case .clear(let t0) = state {
            let k = CGFloat(Ease.outBack(min(1, (animT - t0) / 0.4), 2))
            c.cg.saveGState(); c.cg.translateBy(x: c.width / 2, y: 15); c.cg.scaleBy(x: k, y: k)
            _ = Arcade.display(c, "COURSE CLEAR!", x: 0, y: -6, size: 13, color: Pal.yellow, align: .center)
            c.cg.restoreGState()
        }

        switch state {
        case .title:
            Arcade.titleCard(c, age: animT - stateT, title: "TINY PLUMBER", tagline: "stomp · bonk blocks · grab the flag", accent: Pal.red, accent2: Pal.yellow,
                             hints: [("← →", "walk"), ("Z / B", "run"), ("SPACE / A", "jump")], best: HighScores.get(id), prompt: "PRESS A")
        case .gameOver:
            Arcade.overCard(c, age: animT - stateT, title: "GAME OVER", score: score, best: HighScores.get(id), newBest: newBest, accent: Pal.red,
                            stats: "world 1-\(level) · \(coinCount) coins", prompt: "PRESS A")
        default: break
        }
    }

    /// Demo bot: runs right, hops gaps, walls and enemies.
    func botStep() {
        let T = TileWorld.T
        controls.right = true; controls.left = false; controls.run = false
        let row = max(0, Int((player.y + 0.5) / T))
        func wall(_ a: CGFloat) -> Bool { let col = Int((player.x + player.w + a) / T); return world.get(col, row) != .empty && world.get(col, row) != .platform }
        func gap(_ a: CGFloat) -> Bool { world.get(Int((player.x + player.w + a) / T), row - 1) == .empty }
        let foe = enemies.contains { !$0.dead && $0.squashed == nil && $0.body.x > player.x && $0.body.x - player.x < 20 }
        if player.onGround, wall(3) || gap(4) || foe { controls.jumpPressed = true; controls.jump = true }
        if !player.onGround { controls.jump = player.vy > 70 }
    }

    func drawPlayer(_ c: Canvas) {
        if invuln > 0, Int(animT * 20) % 2 == 0 { return }
        if case .gameOver = state { return }
        let moving = abs(player.vx) > 5
        let frame = Int(animT * (controls.run ? 16 : 10)) % 2 == 0
        let s: Sprite
        if !player.onGround { s = big ? Sprites.bigJump : Sprites.smallJump }
        else if moving && frame { s = big ? Sprites.bigRun : Sprites.smallRun }
        else { s = big ? Sprites.bigStand : Sprites.smallStand }
        let tint: NSColor? = starTime > 0 ? .hsb(CGFloat(animT * 4), 0.7, 1) : nil
        let px = player.x - camX - 0.5
        c.fill(CGRect(x: px + 0.5, y: max(5, player.y) - 0.4, width: 6, height: 0.8), NSColor(white: 0, alpha: 0.2))
        if starTime > 0 { Glow.radial(c, CGPoint(x: px + 3.5, y: player.y + player.h / 2), 9, .hsb(CGFloat(animT * 4), 0.7, 1), alpha: 0.5) }
        let land = CGFloat(Ease.clamp01((animT - landT) / 0.14))
        let sq = 1 - 0.18 * (1 - land)
        c.cg.saveGState()
        c.cg.translateBy(x: px + 3.5, y: player.y); c.cg.scaleBy(x: 2 - sq, y: sq); c.cg.translateBy(x: -(px + 3.5), y: -player.y)
        if case .dying = state { c.sprite(Sprites.smallDie, x: px, y: player.y) } else { c.sprite(s, x: px, y: player.y, flipX: facing < 0, tint: tint) }
        c.cg.restoreGState()
    }

    func overlay(_ c: Canvas, _ title: String, _ sub: String) {
        let w: CGFloat = 520
        let r = CGRect(x: (c.width - w) / 2, y: 1, width: w, height: 28)
        c.roundRect(r, radius: 8, fill: NSColor(white: 0, alpha: 0.78), stroke: Pal.yellow, lineWidth: 1)
        c.text(title, x: r.midX, y: 14, size: 11, color: Pal.yellow, weight: .heavy, align: .center)
        c.text(sub, x: r.midX, y: 3, size: 8, color: .white, align: .center, maxWidth: w - 16)
    }

    // MARK: Input

    public func touchBegan(_ t: StripTouch) {
        if demo { demo = false; startGame(); return }
        if !controls.began(t) {
            if case .playing = state {} else { controls.jumpPressed = true }
        }
    }
    public func touchMoved(_ t: StripTouch) { controls.moved(t) }
    public func touchEnded(_ t: StripTouch) { controls.ended(t) }
    public func keyDown(_ key: GameKey) {
        if demo { demo = false; controls.reset(); startGame(); return }
        controls.key(key, down: true)
    }
    public func keyUp(_ key: GameKey) { controls.key(key, down: false) }
}

/// Deterministic level generation.
public struct SeededRNG {
    var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func nextRaw() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func next(_ n: Int) -> Int { n <= 0 ? 0 : Int(nextRaw() % UInt64(n)) }
}
