import AppKit

/// "Tiny Plumber": a Mario-style side-scroller. ◀ ▶ to walk, B to run, A to jump (hold for higher).
/// Stomp goombas, avoid spikies, bump ? blocks for coins & mushrooms, break bricks when big, grab the flag.
public final class PlumberGame: StripMode {
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
        player = Body(x: 40, y: 5, w: 6, h: big ? 10 : 7)
        camX = 0; invuln = 0; starTime = 0
        controls.reset()
    }

    // MARK: Update

    public func update(dt: Double) {
        animT += dt
        particles.update(CGFloat(dt))
        texts = texts.compactMap { var t = $0; t.life -= dt; t.y += CGFloat(dt) * 12; return t.life > 0 ? t : nil }
        switch state {
        case .title, .gameOver:
            if controls.jumpPressed { controls.jumpPressed = false; startGame() }
        case .dying(let t):
            player.vy -= 500 * CGFloat(dt); player.y += player.vy * CGFloat(dt)
            if animT - t > 2 {
                lives -= 1
                if lives <= 0 { HighScores.submit(id, score); state = .gameOver } else { big = false; buildLevel(); state = .playing }
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

    func startGame() { level = 1; lives = 3; score = 0; coinCount = 0; big = false; buildLevel(); state = .playing }

    func step(_ dt: CGFloat) {
        timeLeft -= Double(dt) * 2
        if timeLeft <= 0 { die(); return }
        invuln = max(0, invuln - Double(dt)); starTime = max(0, starTime - Double(dt))
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
        if player.x < camX { player.x = camX; player.vx = max(0, player.vx) }
        if player.y < -12 { die(); return }

        camX = max(camX, min(player.x - viewW * 0.4, world.width - viewW))
        camX = max(0, camX)

        // Coins
        let pr = player.rect
        coins.removeAll { p in
            guard pr.intersects(CGRect(x: p.x, y: p.y, width: 3, height: 5)) else { return false }
            coinCount += 1; score += 200
            particles.burst(x: p.x + 1.5, y: p.y + 2.5, count: 6, colors: [Pal.yellow, .white], speed: 40, life: 0.35, size: 1)
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
                    particles.burst(x: e.body.midX, y: e.body.y + 3, count: 10, colors: [Pal.brown, Pal.yellow], speed: 60)
                } else if !e.spiky, player.vy < 0, player.y > e.body.y + 2 {
                    e.squashed = animT; player.vy = 110; score += 100
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
            particles.burst(x: flagX, y: 25, count: 40, colors: [Pal.red, Pal.yellow, Pal.cyan, Pal.magenta, .white], speed: 90, life: 1.2)
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
                particles.burst(x: x + 2.5, y: y + 6, count: 8, colors: [Pal.yellow, .white], speed: 50, life: 0.5, size: 1.2)
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
        if big { big = false; player.h = 7; invuln = 1.6; texts.append(FloatText(x: player.x, y: 20, text: "ouch", life: 0.6)) }
        else { die() }
    }

    func die() {
        guard case .playing = state else { return }
        state = .dying(animT)
        player.vy = 150
        particles.burst(x: player.midX, y: player.y + 4, count: 16, colors: [Pal.red, Pal.blue, Pal.skin], speed: 70)
    }

    // MARK: Draw

    public func draw(_ c: Canvas) {
        viewW = c.width
        controls.width = c.width
        c.gradient(c.bounds, [Pal.sky, NSColor(hex: "#9cc4ff")])
        // Parallax hills & clouds
        for i in 0..<30 {
            let hx = CGFloat(i) * 140 - (camX * 0.3).truncatingRemainder(dividingBy: 140 * 30)
            c.circle(center: CGPoint(x: hx, y: 0), radius: 16 + CGFloat(i % 3) * 5, NSColor(hex: "#3d9f43").withAlphaComponent(0.55))
            let cx = CGFloat(i) * 210 - (camX * 0.5 + CGFloat(animT) * 3).truncatingRemainder(dividingBy: 210 * 30) + 60
            for k in 0..<3 { c.circle(center: CGPoint(x: cx + CGFloat(k) * 5, y: 23 + CGFloat(k % 2) * 1.5), radius: 3.2, NSColor(white: 1, alpha: 0.85)) }
        }
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
            let castle = CGRect(x: fx + 25, y: 5, width: 25, height: 15)
            c.fill(castle, NSColor(hex: "#b85c1c"))
            for k in 0..<5 { c.fill(CGRect(x: castle.minX + CGFloat(k) * 5 + 1, y: castle.maxY, width: 3, height: 3), NSColor(hex: "#b85c1c")) }
            c.fill(CGRect(x: castle.midX - 3, y: 5, width: 6, height: 8), .black)
        }
        let coinSprite = Int(animT * 6) % 4 == 3 ? Sprites.coinThin : Sprites.coin
        for p in coins where p.x > camX - 5 && p.x < camX + c.width {
            c.sprite(coinSprite, x: p.x - camX + (coinSprite.width == 1 ? 1 : 0), y: p.y)
        }
        for p in powerUps { c.sprite(p.star ? Sprites.star : Sprites.mushroom, x: p.body.x - camX, y: p.body.y, tint: p.star && Int(animT * 10) % 2 == 0 ? .white : nil) }
        for e in enemies where !e.dead {
            let x = e.body.x - camX
            guard x > -10, x < c.width + 10 else { continue }
            if e.squashed != nil { c.sprite(Sprites.goombaFlat, x: x, y: e.body.y) }
            else if e.spiky { c.sprite(Sprites.spiky, x: x, y: e.body.y, flipX: Int(animT * 4) % 2 == 0) }
            else { c.sprite(Int(animT * 5) % 2 == 0 ? Sprites.goomba1 : Sprites.goomba2, x: x, y: e.body.y) }
        }
        drawPlayer(c)
        particles.draw(c, camX: camX)
        for t in texts { c.text(t.text, x: t.x - camX, y: t.y, size: 7, color: .white, weight: .heavy, align: .center) }

        // HUD
        let hud = "WORLD 1-\(level)   ◎×\(coinCount)   \(String(format: "%06d", score))   ♥\(lives)   ⏱\(max(0, Int(timeLeft)))"
        c.text(hud, x: c.width / 2 + 1, y: 20.5, size: 8, color: NSColor(white: 0, alpha: 0.5), weight: .heavy, mono: true, align: .center)
        c.text(hud, x: c.width / 2, y: 21, size: 8, color: .white, weight: .heavy, mono: true, align: .center)
        controls.draw(c)

        switch state {
        case .title: overlay(c, "TINY PLUMBER", "◀ ▶ walk · B run · A jump (hold = higher) · press A to start · best \(HighScores.get(id))")
        case .gameOver: overlay(c, "GAME OVER", "score \(score) · best \(HighScores.get(id)) · press A to play again")
        default: break
        }
    }

    func drawPlayer(_ c: Canvas) {
        if invuln > 0, Int(animT * 20) % 2 == 0 { return }
        let moving = abs(player.vx) > 5
        let frame = Int(animT * (controls.run ? 16 : 10)) % 2 == 0
        let s: Sprite
        if !player.onGround { s = big ? Sprites.bigJump : Sprites.smallJump }
        else if moving && frame { s = big ? Sprites.bigRun : Sprites.smallRun }
        else { s = big ? Sprites.bigStand : Sprites.smallStand }
        let tint: NSColor? = starTime > 0 ? .hsb(CGFloat(animT * 4), 0.7, 1) : nil
        c.sprite(s, x: player.x - camX - 0.5, y: player.y, flipX: facing < 0, tint: tint)
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
        if !controls.began(t) {
            if case .playing = state {} else { controls.jumpPressed = true }
        }
    }
    public func touchMoved(_ t: StripTouch) { controls.moved(t) }
    public func touchEnded(_ t: StripTouch) { controls.ended(t) }
    public func keyDown(_ key: GameKey) { controls.key(key, down: true) }
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
