import AppKit

/// "Neon Dash": endless auto-runner platformer. Tap anywhere to jump, tap again mid-air to double jump,
/// hold for a higher jump. Stomp bots, grab coins, don't fall or smack into walls.
public final class DashGame: StripMode {
    public let id = "dash"
    public let title = "Neon Dash"
    public let icon = "figure.run"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    enum State { case title, playing, dead(Double) }
    let world = TileWorld()
    let particles = Particles()
    var state: State = .title
    var player = Body(x: 40, y: 10, w: 5, h: 6)
    var speed: CGFloat = 90
    var jumps = 0
    var holding = false
    var enemies: [Body] = []
    var coins: [CGPoint] = []
    var camX: CGFloat = 0
    var score = 0, coinCount = 0
    var t = 0.0
    var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))
    var groundH = 1

    public init() { reset() }
    public func activate(_ ctx: ModeContext) { holding = false }

    func reset() {
        world.cols = []; world.origin = 0; world.leftWall = false
        enemies = []; coins = []
        groundH = 1
        for _ in 0..<60 { appendColumn(groundH, platform: false) }
        player = Body(x: 40, y: 5, w: 5, h: 6)
        speed = 90; camX = 0; score = 0; coinCount = 0; jumps = 0
    }

    func appendColumn(_ h: Int, platform: Bool, spike: Bool = false) {
        var col = world.emptyColumn()
        for r in 0..<h { col[r] = .ground }
        if platform { col[3] = .platform }
        if spike, h < TileWorld.rows { col[h] = .spike }
        world.append(col)
    }

    func generate(until end: Int) {
        while world.endColumn < end {
            let c = world.endColumn
            switch rng.next(10) {
            case 0, 1: // gap
                let w = 2 + rng.next(min(5, 2 + Int(speed / 60)))
                for _ in 0..<w { appendColumn(0, platform: false) }
                for i in 0..<w { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: CGFloat(groundH) * 5 + 12)) }
            case 2: // step up/down
                groundH = max(1, min(2, groundH + (rng.next(2) == 0 ? 1 : -1)))
                for _ in 0..<(6 + rng.next(6)) { appendColumn(groundH, platform: false) }
            case 3: // floating platform over a gap
                let w = 6 + rng.next(5)
                for i in 0..<w { appendColumn(i < 2 || i > w - 3 ? groundH : 0, platform: i >= 1 && i < w - 1) }
                for i in 1..<(w - 1) where i % 2 == 0 { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: 21)) }
            case 4: // spikes
                let w = 1 + rng.next(2)
                for _ in 0..<3 { appendColumn(groundH, platform: false) }
                for _ in 0..<w { appendColumn(groundH, platform: false, spike: true) }
                for _ in 0..<4 { appendColumn(groundH, platform: false) }
            case 5, 6: // bot
                for _ in 0..<10 { appendColumn(groundH, platform: false) }
                enemies.append(Body(x: CGFloat(c + 7) * 5, y: CGFloat(groundH) * 5, w: 6, h: 6))
            default:
                for i in 0..<(8 + rng.next(8)) {
                    appendColumn(groundH, platform: false)
                    if i % 3 == 0, rng.next(2) == 0 { coins.append(CGPoint(x: CGFloat(c + i) * 5 + 1, y: CGFloat(groundH) * 5 + 3)) }
                }
            }
        }
    }

    public func update(dt: Double) {
        t += dt
        let dt = CGFloat(dt)
        particles.update(dt)
        guard case .playing = state else { return }
        speed = min(220, speed + dt * 2.2)
        player.vx = speed
        let g: CGFloat = holding && player.vy > 0 ? 330 : 680
        player.vy = max(-240, player.vy - g * dt)
        world.move(&player, dt: dt)
        if player.onGround { jumps = 0 }
        if player.hitWall || player.y < -10 || world.touches(player, .spike) { die(); return }
        camX = player.x - 140
        generate(until: Int((camX + 1300) / 5))
        world.dropBefore(Int(camX / 5) - 4)
        let pr = player.rect
        coins.removeAll { p in
            if p.x < camX - 20 { return true }
            guard pr.intersects(CGRect(x: p.x, y: p.y, width: 3, height: 5)) else { return false }
            coinCount += 1
            particles.burst(x: p.x, y: p.y, count: 5, colors: [Pal.yellow, Pal.cyan], speed: 40, life: 0.3, size: 1)
            return true
        }
        for i in enemies.indices.reversed() {
            var e = enemies[i]
            e.vx = -18; e.vy = max(-200, e.vy - 600 * dt)
            world.move(&e, dt: dt)
            if e.x < camX - 20 || e.y < -10 { enemies.remove(at: i); continue }
            if e.rect.insetBy(dx: 0.5, dy: 0.5).intersects(pr) {
                if player.vy < 0, player.y > e.y + 2 {
                    player.vy = 140; jumps = 1; coinCount += 5
                    particles.burst(x: e.midX, y: e.y + 3, count: 12, colors: [Pal.magenta, Pal.cyan, .white], speed: 70)
                    enemies.remove(at: i); continue
                }
                die(); return
            }
            enemies[i] = e
        }
        score = Int(player.x / 5) + coinCount * 10
    }

    func jump() {
        switch state {
        case .title: state = .playing; reset()
        case .dead(let at): if t - at > 0.6 { state = .playing; reset() }
        case .playing:
            if jumps < 2 {
                player.vy = jumps == 0 ? 135 : 120
                jumps += 1
                particles.burst(x: player.midX, y: player.y, count: 6, colors: [Pal.cyan, Pal.magenta], speed: 30, life: 0.3, size: 1)
            }
        }
    }

    func die() {
        state = .dead(t)
        HighScores.submit(id, score)
        particles.burst(x: player.midX, y: player.y + 3, count: 30, colors: [Pal.magenta, Pal.cyan, .white], speed: 90, life: 0.9)
    }

    public func draw(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#12002b"), NSColor(hex: "#2b0040")])
        for i in 0..<50 { // stars
            let x = (CGFloat(i * 131) - camX * 0.05).truncatingRemainder(dividingBy: c.width)
            c.fill(CGRect(x: x < 0 ? x + c.width : x, y: CGFloat((i * 53) % 28) + 1, width: 1, height: 1), NSColor(white: 1, alpha: 0.6))
        }
        for i in 0..<40 { // skyline
            let bw: CGFloat = 26, x = CGFloat(i) * bw - (camX * 0.25).truncatingRemainder(dividingBy: bw * 40)
            let h = CGFloat(8 + (i * 37) % 14)
            c.fill(CGRect(x: x, y: 0, width: bw - 3, height: h), NSColor(hex: "#3a0a5a"))
            if (i * 7) % 3 == 0 { c.fill(CGRect(x: x + 4, y: h - 4, width: 2, height: 1.5), Pal.yellow.withAlphaComponent(0.7)) }
        }
        let T = TileWorld.T
        let c0 = Int(camX / T) - 1, c1 = Int((camX + c.width) / T) + 1
        for col in c0...c1 { for r in 0..<TileWorld.rows {
            let tile = world.get(col, r)
            if tile != .empty { TileArt.draw(c, tile, x: CGFloat(col) * T - camX, y: CGFloat(r) * T, time: t, night: true) }
        } }
        for p in coins { c.sprite(Sprites.coin, x: p.x - camX, y: p.y) }
        for e in enemies {
            c.sprite(Sprites.goomba1, x: e.x - camX, y: e.y, tint: Int(t * 6) % 2 == 0 ? Pal.cyan : Pal.magenta)
        }
        if case .dead = state {} else {
            for k in 1...4 { c.fill(CGRect(x: player.x - camX - CGFloat(k) * 4, y: player.y + 2, width: 3, height: 2), Pal.cyan.withAlphaComponent(0.5 / CGFloat(k))) }
            c.sprite(Int(t * 12) % 2 == 0 ? Sprites.runner : Sprites.runner2, x: player.x - camX, y: player.y)
        }
        particles.draw(c, camX: camX)
        c.text("\(score)", x: c.width - 10, y: 19, size: 9, color: .white, weight: .heavy, mono: true, align: .right)
        c.text("best \(HighScores.get(id))", x: c.width - 10, y: 10, size: 7, color: Pal.cyan, mono: true, align: .right)
        switch state {
        case .title: banner(c, "NEON DASH", "tap anywhere to jump · tap again to double-jump · hold = higher · stomp bots")
        case .dead: banner(c, "WIPEOUT · \(score)", "tap to run again · best \(HighScores.get(id))")
        default: break
        }
    }

    func banner(_ c: Canvas, _ a: String, _ b: String) {
        let r = CGRect(x: c.width / 2 - 250, y: 1, width: 500, height: 28)
        c.roundRect(r, radius: 8, fill: NSColor(white: 0, alpha: 0.75), stroke: Pal.magenta, lineWidth: 1)
        c.text(a, x: r.midX, y: 14, size: 11, color: Pal.cyan, weight: .heavy, align: .center)
        c.text(b, x: r.midX, y: 3, size: 8, color: .white, align: .center)
    }

    public func touchBegan(_ t: StripTouch) { holding = true; jump() }
    public func touchEnded(_ t: StripTouch) { holding = false }
    public func keyDown(_ key: GameKey) { if key == .jump || key == .up { holding = true; jump() } }
    public func keyUp(_ key: GameKey) { if key == .jump || key == .up { holding = false } }
}

/// "Gravity Flip": VVVVVV-style. Tap to flip gravity between floor and ceiling. Avoid spikes and gaps.
public final class FlipGame: StripMode {
    public let id = "flip"
    public let title = "Gravity Flip"
    public let icon = "arrow.up.arrow.down"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    enum State { case title, playing, dead(Double) }
    let world = TileWorld()
    let particles = Particles()
    var state: State = .title
    var player = Body(x: 40, y: 5, w: 5, h: 6)
    var down = true
    var speed: CGFloat = 80
    var camX: CGFloat = 0
    var gems: [CGPoint] = []
    var gemCount = 0, score = 0
    var t = 0.0
    var trail: [CGPoint] = []
    var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970) ^ 0xF11F)

    public init() { reset() }
    public func activate(_ ctx: ModeContext) {}

    func reset() {
        world.cols = []; world.origin = 0; world.leftWall = false
        gems = []; trail = []
        for _ in 0..<60 { column(floor: true, ceil: true) }
        player = Body(x: 40, y: 5, w: 5, h: 6)
        down = true; speed = 80; camX = 0; gemCount = 0; score = 0
    }

    func column(floor: Bool, ceil: Bool, floorSpike: Bool = false, ceilSpike: Bool = false) {
        var col = world.emptyColumn()
        if floor { col[0] = .ground }
        if ceil { col[5] = .ground }
        if floorSpike { col[1] = .spike }
        if ceilSpike { col[4] = .spike }
        world.append(col)
    }

    func generate(until end: Int) {
        while world.endColumn < end {
            let c = world.endColumn
            switch rng.next(7) {
            case 0: // floor gap → must be on ceiling
                for _ in 0..<(3 + rng.next(4)) { column(floor: false, ceil: true) }
            case 1: // ceiling gap → must be on floor
                for _ in 0..<(3 + rng.next(4)) { column(floor: true, ceil: false) }
            case 2: // floor spikes
                for i in 0..<(2 + rng.next(3)) { column(floor: true, ceil: true, floorSpike: i > 0) }
            case 3: // ceiling spikes
                for i in 0..<(2 + rng.next(3)) { column(floor: true, ceil: true, ceilSpike: i > 0) }
            case 4: // zig-zag
                column(floor: true, ceil: true, floorSpike: true); column(floor: true, ceil: true)
                column(floor: true, ceil: true); column(floor: true, ceil: true, ceilSpike: true)
                column(floor: true, ceil: true); column(floor: true, ceil: true)
            default:
                for _ in 0..<(5 + rng.next(5)) { column(floor: true, ceil: true) }
                gems.append(CGPoint(x: CGFloat(c + 3) * 5, y: rng.next(2) == 0 ? 6 : 20))
            }
            for _ in 0..<3 { column(floor: true, ceil: true) }
        }
    }

    public func update(dt: Double) {
        t += dt
        let dt = CGFloat(dt)
        particles.update(dt)
        guard case .playing = state else { return }
        speed = min(190, speed + dt * 2)
        player.vx = speed
        player.vy += (down ? -620 : 620) * dt
        player.vy = max(-220, min(220, player.vy))
        world.move(&player, dt: dt, gravityDown: down)
        if player.hitWall || player.y < -12 || player.y > 42 || world.touches(player, .spike, inset: 1.2) { die(); return }
        trail.append(CGPoint(x: player.x, y: player.y))
        if trail.count > 10 { trail.removeFirst() }
        camX = player.x - 160
        generate(until: Int((camX + 1300) / 5))
        world.dropBefore(Int(camX / 5) - 4)
        let pr = player.rect
        gems.removeAll { g in
            if g.x < camX - 20 { return true }
            guard pr.intersects(CGRect(x: g.x, y: g.y, width: 3, height: 4)) else { return false }
            gemCount += 1
            particles.burst(x: g.x, y: g.y, count: 8, colors: [Pal.cyan, .white], speed: 50, life: 0.4, size: 1)
            return true
        }
        score = Int(player.x / 5) + gemCount * 25
    }

    func tap() {
        switch state {
        case .title: reset(); state = .playing
        case .dead(let at): if t - at > 0.6 { reset(); state = .playing }
        case .playing:
            down.toggle()
            particles.burst(x: player.midX, y: player.y + 3, count: 6, colors: [Pal.magenta, .white], speed: 30, life: 0.25, size: 1)
        }
    }

    func die() {
        state = .dead(t)
        HighScores.submit(id, score)
        particles.burst(x: player.midX, y: player.y + 3, count: 30, colors: [Pal.cyan, Pal.magenta, .white], speed: 90, life: 0.9, gravity: 0)
    }

    public func draw(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#001a2c"), NSColor(hex: "#00303f")], horizontal: true)
        for i in 0..<60 {
            let x = (CGFloat(i * 89) - camX * 0.4).truncatingRemainder(dividingBy: c.width)
            c.fill(CGRect(x: x < 0 ? x + c.width : x, y: CGFloat((i * 41) % 20) + 5, width: 6, height: 0.5), Pal.cyan.withAlphaComponent(0.15))
        }
        let T = TileWorld.T
        let c0 = Int(camX / T) - 1, c1 = Int((camX + c.width) / T) + 1
        for col in c0...c1 { for r in 0..<TileWorld.rows {
            let tile = world.get(col, r)
            let x = CGFloat(col) * T - camX, y = CGFloat(r) * T
            if tile == .spike {
                if r >= 3 { TileArt.spikeDown(c, x: x, y: y, color: Pal.magenta) } else { TileArt.draw(c, .spike, x: x, y: y, time: t, night: true) }
            } else if tile == .ground {
                c.fill(CGRect(x: x, y: y, width: T, height: T), NSColor(hex: "#0b4f6c"))
                c.fill(CGRect(x: x, y: r == 0 ? y + T - 0.8 : y, width: T, height: 0.8), Pal.cyan)
            }
        } }
        for g in gems { c.sprite(Sprites.gem, x: g.x - camX, y: g.y + CGFloat(sin(t * 4 + Double(g.x))) * 0.8) }
        if case .dead = state {} else {
            for (i, p) in trail.enumerated() {
                c.fill(CGRect(x: p.x - camX + 1, y: p.y + 1, width: 3, height: 4), Pal.magenta.withAlphaComponent(CGFloat(i) / CGFloat(trail.count) * 0.4))
            }
            c.cg.saveGState()
            if !down { c.cg.translateBy(x: 0, y: player.y * 2 + player.h); c.cg.scaleBy(x: 1, y: -1) }
            c.sprite(Sprites.runner, x: player.x - camX, y: player.y)
            c.cg.restoreGState()
        }
        particles.draw(c, camX: camX)
        c.text("\(score)  ◆\(gemCount)", x: c.width - 10, y: 10, size: 9, color: .white, weight: .heavy, mono: true, align: .right)
        switch state {
        case .title: banner(c, "GRAVITY FLIP", "tap to flip gravity · dodge spikes & gaps · best \(HighScores.get(id))")
        case .dead: banner(c, "SPLAT · \(score)", "tap to retry · best \(HighScores.get(id))")
        default: break
        }
    }

    func banner(_ c: Canvas, _ a: String, _ b: String) {
        let r = CGRect(x: c.width / 2 - 230, y: 1, width: 460, height: 28)
        c.roundRect(r, radius: 8, fill: NSColor(white: 0, alpha: 0.75), stroke: Pal.cyan, lineWidth: 1)
        c.text(a, x: r.midX, y: 14, size: 11, color: Pal.magenta, weight: .heavy, align: .center)
        c.text(b, x: r.midX, y: 3, size: 8, color: .white, align: .center)
    }

    public func touchBegan(_ t: StripTouch) { tap() }
    public func keyDown(_ key: GameKey) { if key == .jump || key == .up || key == .down { tap() } }
}
