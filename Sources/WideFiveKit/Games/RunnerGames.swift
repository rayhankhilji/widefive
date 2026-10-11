import AppKit

/// "Neon Dash": endless auto-runner platformer. Tap anywhere to jump, tap again mid-air to double jump,
/// hold for a higher jump. Stomp bots, grab coins, don't fall or smack into walls.
public final class DashGame: StripMode, DemoStartable {
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
    var demo = false
    var stateT = 0.0
    var pulse: CGFloat = 0
    var newBest = false
    let shake = Shake(maxOffset: 2.6)
    var pops: [Arcade.Popup] = []

    public func startDemo() { demo = true; reset(); state = .playing; stateT = t }

    public init() { reset() }
    public func activate(_ ctx: ModeContext) { holding = false }

    func reset() {
        world.cols = []; world.origin = 0; world.leftWall = false
        enemies = []; coins = []
        groundH = 1
        for _ in 0..<60 { appendColumn(groundH, platform: false) }
        player = Body(x: 200, y: 5, w: 5, h: 6)
        speed = 90; camX = player.x - 140; score = 0; coinCount = 0; jumps = 0
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
        particles.update(dt); shake.update(dt); Arcade.update(&pops, Double(dt))
        pulse = max(0, pulse - dt * 3)
        guard case .playing = state else { return }
        if demo { botDash() }
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
            coinCount += 1; pulse = 1
            particles.burst(x: p.x + 1.5, y: p.y + 2.5, count: 8, colors: [Pal.yellow, .white], speed: 45, life: 0.35, size: 1.4, gravity: 0, kind: .sparkle, drag: 4)
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
                    particles.burst(x: e.midX, y: e.y + 3, count: 16, colors: [Pal.magenta, Pal.cyan, .white], speed: 80, life: 0.5, size: 1.5, kind: .shard)
                    particles.ring(x: e.midX, y: e.y + 3, color: Pal.cyan, radius: 10)
                    pops.append(.init(x: e.midX, y: e.y + 9, text: "STOMP +50", color: Pal.cyan)); shake.add(0.25); pulse = 1
                    enemies.remove(at: i); continue
                }
                die(); return
            }
            enemies[i] = e
        }
        score = Int(player.x / 5) + coinCount * 10
    }

    func jump(auto: Bool = false) {
        switch state {
        case .title: state = .playing; reset(); stateT = t
        case .dead(let at): if t - at > 0.6 { demo = false; state = .playing; reset(); stateT = t }
        case .playing:
            if demo, !auto { demo = false; state = .playing; reset(); stateT = t; return }
            if jumps < 2 {
                player.vy = jumps == 0 ? 135 : 120
                jumps += 1
                particles.burst(x: player.midX, y: player.y, count: 6, colors: [jumps == 2 ? Pal.magenta : NSColor(white: 1, alpha: 0.8)], speed: 30, life: 0.3, size: 1.2, gravity: 0,
                                kind: jumps == 2 ? .ring : .dot, drag: 4, direction: -.pi / 2, spread: 2.5)
            }
        }
    }

    func die() {
        state = .dead(t); stateT = t
        newBest = HighScores.submit(id, score)
        shake.add(0.8)
        particles.flash(x: player.midX, y: player.y + 3, color: .white, radius: 18, life: 0.15)
        particles.burst(x: player.midX, y: player.y + 3, count: 30, colors: [Pal.magenta, Pal.cyan, .white], speed: 90, life: 0.9, size: 1.6, kind: .shard)
    }

    /// Demo bot: jumps at gaps, spikes, walls and bots; double-jumps when a gap is still under it at the apex.
    func botDash() {
        let T = TileWorld.T
        let row = max(0, Int((player.y - 0.5) / T))
        func danger(_ ahead: CGFloat) -> Bool {
            let col = Int((player.x + ahead) / T)
            return world.get(col, row) == .empty || world.get(col, row + 1) != .empty || world.get(col, row + 2) == .spike
        }
        let bot = enemies.contains { $0.x > player.x && $0.x - player.x < 22 }
        if player.onGround, danger(10) || danger(14) || bot { holding = true; jump(auto: true) }
        else if !player.onGround, player.vy < -30, jumps < 2, world.get(Int((player.x + 8) / T), max(0, row - 1)) == .empty, player.y < 12 { jump(auto: true) }
        else if player.vy < 0 { holding = false }
    }

    public func draw(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#3a0a5c"), NSColor(hex: "#0b0220")].reversed())
        let sun = CGPoint(x: c.width * 0.62, y: 6)
        Glow.radial(c, sun, 80, NSColor(hex: "#ff3d9a"), alpha: 0.35)
        c.clip(CGRect(x: 0, y: 4, width: c.width, height: 26)) {
            c.gradient(CGRect(x: sun.x - 16, y: sun.y - 16, width: 32, height: 32), [NSColor(hex: "#ff3d9a"), NSColor(hex: "#ffd23f")], radius: 16)
        }
        for k in 0..<4 { c.fill(CGRect(x: sun.x - 17, y: 6 + CGFloat(k) * 3, width: 34, height: 0.6 + CGFloat(k) * 0.25), NSColor(hex: "#3a0a5c")) }
        for i in 0..<50 { // stars
            let x = (CGFloat(i * 131) - camX * 0.05).truncatingRemainder(dividingBy: c.width)
            c.fill(CGRect(x: x < 0 ? x + c.width : x, y: CGFloat((i * 53) % 18) + 12, width: 0.8, height: 0.8), NSColor(white: 1, alpha: 0.3 + CGFloat(i % 3) * 0.15))
        }
        for (layer, (f, col, hMin, win)) in [(0.12, NSColor(hex: "#2a0a4a"), 10, NSColor(hex: "#ff6bd6")), (0.3, NSColor(hex: "#1a0633"), 6, NSColor(hex: "#21e6ff"))].enumerated() {
            let bw: CGFloat = layer == 0 ? 30 : 22
            let off = (camX * CGFloat(f)).truncatingRemainder(dividingBy: bw)
            let base = Int(camX * CGFloat(f) / bw)
            var x = -off; var i = base
            while x < c.width {
                let h = CGFloat(hMin + (i &* 37 &+ layer * 11) % 12)
                c.fill(CGRect(x: x, y: 0, width: bw - 3, height: h), col)
                c.fill(CGRect(x: x, y: h - 0.5, width: bw - 3, height: 0.5), win.withAlphaComponent(0.35))
                if (i &* 7) % 3 == 0 { c.fill(CGRect(x: x + 4, y: h - 4, width: 2, height: 1.2), win.withAlphaComponent(0.6)) }
                x += bw; i += 1
            }
        }
        c.cg.saveGState()
        shake.apply(c)
        let T = TileWorld.T
        let c0 = Int(camX / T) - 1, c1 = Int((camX + c.width) / T) + 1
        for col in c0...c1 { for r in 0..<TileWorld.rows {
            let tile = world.get(col, r)
            if tile != .empty { TileArt.draw(c, tile, x: CGFloat(col) * T - camX, y: CGFloat(r) * T, time: t, night: true) }
        } }
        for p in coins {
            let cp = CGPoint(x: p.x - camX + 1.5, y: p.y + 2.5 + CGFloat(sin(t * 4 + Double(p.x) * 0.1)) * 0.6)
            Glow.radial(c, cp, 4, Pal.yellow, alpha: 0.35)
            Icons.coin(c, cp, 2.2, spin: t * 4 + Double(p.x) * 0.05)
        }
        for e in enemies { RunnerArt.bot(c, x: e.x - camX, y: e.y, t: t) }
        if case .dead = state {} else {
            for k in 1...5 {
                let a = 0.45 / CGFloat(k)
                c.roundRect(CGRect(x: player.x - camX - CGFloat(k) * 3.5, y: player.y + 1.5, width: 3, height: 4), radius: 1, fill: (k % 2 == 0 ? Pal.magenta : Pal.cyan).withAlphaComponent(a))
            }
            RunnerArt.runner(c, x: player.midX - camX, y: player.y, t: t, air: !player.onGround, vy: player.vy, color: Pal.cyan)
        }
        particles.draw(c, camX: camX)
        Arcade.draw(c, pops, camX: camX)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.3)
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init("COINS", "\(coinCount)", color: Pal.yellow), .init("SPEED", "\(Int(speed))")], accent: Pal.magenta, pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "NEON DASH", tagline: "auto-run · stomp bots · don't fall", accent: Pal.cyan, accent2: Pal.magenta,
                             hints: [("SPACE ↑", "jump ×2"), ("HOLD", "higher")], best: HighScores.get(id))
        case .dead:
            Arcade.overCard(c, age: t - stateT, title: "WIPEOUT", score: score, best: HighScores.get(id), newBest: newBest, accent: Pal.magenta, stats: "\(Int(player.x / 5))m · \(coinCount) coins")
        default: break
        }
    }

    public func touchBegan(_ t: StripTouch) { holding = true; jump() }
    public func touchEnded(_ t: StripTouch) { holding = false }
    public func keyDown(_ key: GameKey) { if key == .jump || key == .up { holding = true; jump() } }
    public func keyUp(_ key: GameKey) { if key == .jump || key == .up { holding = false } }
}

/// "Gravity Flip": VVVVVV-style. Tap to flip gravity between floor and ceiling. Avoid spikes and gaps.
public final class FlipGame: StripMode, DemoStartable {
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
    var player = Body(x: 200, y: 5, w: 5, h: 6)
    var down = true
    var speed: CGFloat = 80
    var camX: CGFloat = 0
    var gems: [CGPoint] = []
    var gemCount = 0, score = 0
    var t = 0.0
    var trail: [CGPoint] = []
    var demo = false
    var stateT = 0.0
    var flipT = -9.0
    var pulse: CGFloat = 0
    var newBest = false
    let shake = Shake(maxOffset: 2.6)
    var pops: [Arcade.Popup] = []

    public func startDemo() { demo = true; reset(); state = .playing; stateT = t }
    var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970) ^ 0xF11F)

    public init() { reset() }
    public func activate(_ ctx: ModeContext) {}

    func reset() {
        world.cols = []; world.origin = 0; world.leftWall = false
        gems = []; trail = []
        for _ in 0..<60 { column(floor: true, ceil: true) }
        player = Body(x: 200, y: 5, w: 5, h: 6)
        down = true; speed = 80; camX = player.x - 160; gemCount = 0; score = 0
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
            for _ in 0..<5 { column(floor: true, ceil: true) }
        }
    }

    public func update(dt: Double) {
        t += dt
        let dt = CGFloat(dt)
        particles.update(dt); shake.update(dt); Arcade.update(&pops, Double(dt))
        pulse = max(0, pulse - dt * 3)
        guard case .playing = state else { return }
        if demo { botFlip() }
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
            gemCount += 1; pulse = 1
            particles.burst(x: g.x + 1.5, y: g.y + 2, count: 12, colors: [Pal.cyan, .white], speed: 55, life: 0.45, size: 1.5, gravity: 0, kind: .sparkle, drag: 4)
            particles.ring(x: g.x + 1.5, y: g.y + 2, color: Pal.cyan, radius: 9)
            pops.append(.init(x: g.x, y: g.y + (g.y > 15 ? -5 : 7), text: "+25", color: Pal.cyan))
            return true
        }
        score = Int(player.x / 5) + gemCount * 25
    }

    func tap(auto: Bool = false) {
        switch state {
        case .title: reset(); state = .playing; stateT = t
        case .dead(let at): if t - at > 0.6 { demo = false; reset(); state = .playing; stateT = t }
        case .playing:
            if demo, !auto { demo = false; reset(); stateT = t; return }
            down.toggle(); flipT = t
            particles.burst(x: player.midX, y: player.y + 3, count: 8, colors: [Pal.magenta, .white], speed: 40, life: 0.3, size: 1.2, gravity: 0, kind: .streak, drag: 4,
                            direction: down ? .pi / 2 : -.pi / 2, spread: 1.2)
        }
    }

    func die() {
        state = .dead(t); stateT = t
        newBest = HighScores.submit(id, score)
        shake.add(0.8)
        particles.flash(x: player.midX, y: player.y + 3, color: .white, radius: 18, life: 0.15)
        particles.burst(x: player.midX, y: player.y + 3, count: 30, colors: [Pal.cyan, Pal.magenta, .white], speed: 90, life: 0.9, size: 1.6, gravity: 0, kind: .shard, drag: 1.5)
    }

    /// Demo bot: flips when the surface it's running on ends or grows spikes, if the other side is clear.
    func botFlip() {
        guard player.onGround, t - flipT > 0.15 else { return }
        let T = TileWorld.T
        func bad(_ floor: Bool, _ ahead: CGFloat) -> Bool {
            let col = Int((player.x + ahead) / T)
            return floor ? (world.get(col, 0) != .ground || world.get(col, 1) == .spike) : (world.get(col, 5) != .ground || world.get(col, 4) == .spike)
        }
        let reach = speed * 0.32 + 12
        let soon = stride(from: CGFloat(9), through: 12 + speed * 0.16, by: 2).contains { bad(down, $0) }
        let clear = !stride(from: reach - 8, through: reach + 8, by: 2).contains { bad(!down, $0) }
        if soon, clear { tap(auto: true) }
    }

    public func draw(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#002a3a"), NSColor(hex: "#00111c"), NSColor(hex: "#002a3a")])
        for i in 0..<5 { // drifting aurora bands
            let y = 8 + CGFloat(i) * 3.2 + CGFloat(sin(t * 0.6 + Double(i))) * 1.5
            c.gradient(CGRect(x: 0, y: y, width: c.width, height: 2.2), [Pal.cyan.withAlphaComponent(0), Pal.cyan.withAlphaComponent(0.05 + CGFloat(i % 2) * 0.03), Pal.magenta.withAlphaComponent(0)], horizontal: true)
        }
        for layer in 0..<2 {
            let f: CGFloat = layer == 0 ? 0.15 : 0.45
            for i in 0..<50 {
                let x = (CGFloat(i * 89 + layer * 41) - camX * f).truncatingRemainder(dividingBy: c.width)
                let len: CGFloat = layer == 0 ? 3 : 8
                c.fill(CGRect(x: x < 0 ? x + c.width : x, y: CGFloat((i * 41 + layer * 7) % 18) + 6, width: len, height: 0.5), Pal.cyan.withAlphaComponent(layer == 0 ? 0.12 : 0.22))
            }
        }
        c.cg.saveGState()
        shake.apply(c)
        let T = TileWorld.T
        let c0 = Int(camX / T) - 1, c1 = Int((camX + c.width) / T) + 1
        for col in c0...c1 { for r in 0..<TileWorld.rows {
            let tile = world.get(col, r)
            let x = CGFloat(col) * T - camX, y = CGFloat(r) * T
            if tile == .spike {
                if r >= 3 { TileArt.spikeDown(c, x: x, y: y, color: Pal.magenta) } else { TileArt.draw(c, .spike, x: x, y: y, time: t, night: true) }
            } else if tile == .ground {
                c.gradient(CGRect(x: x, y: y, width: T, height: T), r == 0 ? [NSColor(hex: "#0e5f80"), NSColor(hex: "#06283a")] : [NSColor(hex: "#06283a"), NSColor(hex: "#0e5f80")])
                if col % 2 == 0 { c.fill(CGRect(x: x + 1, y: y + 1.5, width: 0.6, height: 2), Pal.cyan.withAlphaComponent(0.15)) }
                let edge = CGRect(x: x, y: r == 0 ? y + T - 0.7 : y, width: T, height: 0.7)
                c.fill(edge, Pal.cyan)
                if world.get(col - 1, r) != .ground || world.get(col + 1, r) != .ground { Glow.radial(c, CGPoint(x: edge.midX, y: edge.midY), 4, Pal.cyan, alpha: 0.4) }
            }
        } }
        for g in gems {
            let gp = CGPoint(x: g.x - camX + 1.5, y: g.y + 2 + CGFloat(sin(t * 4 + Double(g.x))) * 0.8)
            Glow.radial(c, gp, 6, Pal.cyan, alpha: 0.4 + 0.2 * CGFloat(sin(t * 6)))
            Icons.gem(c, gp, 2.6, Pal.cyan)
        }
        if case .dead = state {} else {
            for (i, p) in trail.enumerated() {
                let k = CGFloat(i) / CGFloat(max(1, trail.count))
                c.roundRect(CGRect(x: p.x - camX + 1, y: p.y + 1, width: 3, height: 4), radius: 1.2, fill: Pal.magenta.withAlphaComponent(k * 0.45))
            }
            c.cg.saveGState()
            let flipK = CGFloat(Ease.outBack((t - flipT) / 0.2, 2))
            let sy: CGFloat = down ? (-1 + 2 * flipK) : (1 - 2 * flipK)
            c.cg.translateBy(x: 0, y: player.y + player.h / 2); c.cg.scaleBy(x: 1, y: max(-1, min(1, sy))); c.cg.translateBy(x: 0, y: -(player.y + player.h / 2))
            RunnerArt.runner(c, x: player.midX - camX, y: player.y, t: t, air: !player.onGround, vy: 0, color: Pal.magenta)
            c.cg.restoreGState()
        }
        particles.draw(c, camX: camX)
        Arcade.draw(c, pops, camX: camX)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.3)
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init("GEMS", "\(gemCount)", color: Pal.cyan), .init("BEST", "\(max(score, HighScores.get(id)))", color: NSColor(white: 0.75, alpha: 1))], accent: Pal.cyan, pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "GRAVITY FLIP", tagline: "flip between floor & ceiling", accent: Pal.magenta, accent2: Pal.cyan,
                             hints: [("SPACE ↑ ↓", "flip"), ("TAP", "flip")], best: HighScores.get(id))
        case .dead:
            Arcade.overCard(c, age: t - stateT, title: "SPLAT", score: score, best: HighScores.get(id), newBest: newBest, accent: Pal.magenta, stats: "\(Int(player.x / 5))m · \(gemCount) gems")
        default: break
        }
    }

    public func touchBegan(_ t: StripTouch) { tap() }
    public func keyDown(_ key: GameKey) { if key == .jump || key == .up || key == .down { tap() } }
}

/// Vector art shared by the runners.
enum RunnerArt {
    /// Neon runner, ~9pt tall, feet at `y`. Run cycle on the ground, tuck in the air.
    static func runner(_ c: Canvas, x: CGFloat, y: CGFloat, t: Double, air: Bool, vy: CGFloat, color: NSColor) {
        let ph = t * 16
        let hip = CGPoint(x: x, y: y + 3.6 + (air ? 0 : CGFloat(abs(sin(ph))) * 0.5))
        let neck = CGPoint(x: hip.x + 1.2, y: hip.y + 3.4)
        func limb(_ pts: [CGPoint], _ w: CGFloat, _ col: NSColor) {
            c.cg.setStrokeColor(col.cgColor); c.cg.setLineWidth(w); c.cg.setLineCap(.round); c.cg.setLineJoin(.round)
            c.cg.beginPath(); c.cg.move(to: pts[0]); for p in pts.dropFirst() { c.cg.addLine(to: p) }; c.cg.strokePath()
        }
        let dark = color.blended(withFraction: 0.5, of: .black) ?? color
        let s = CGFloat(sin(ph)), co = CGFloat(cos(ph))
        let f1 = air ? CGPoint(x: hip.x + 2.2, y: hip.y - 1.6) : CGPoint(x: hip.x + s * 2.4, y: y + max(0, co) * 1.2)
        let f2 = air ? CGPoint(x: hip.x - 1.6, y: hip.y - 2.6) : CGPoint(x: hip.x - s * 2.4, y: y + max(0, -co) * 1.2)
        func knee(_ f: CGPoint) -> CGPoint { CGPoint(x: (f.x + hip.x) / 2 + 0.9, y: (f.y + hip.y) / 2 + 0.2) }
        Glow.radial(c, CGPoint(x: x, y: y + 4.5), 7, color, alpha: 0.25)
        limb([hip, knee(f2), f2], 1.3, dark)
        limb([CGPoint(x: neck.x - 0.3, y: neck.y - 0.8), CGPoint(x: neck.x - 1.6 + s * 1.2, y: neck.y - 2.4), CGPoint(x: neck.x - 0.6 + s * 1.8, y: neck.y - 3.6)], 1.0, dark)
        limb([hip, neck], 2.2, color)
        limb([hip, knee(f1), f1], 1.3, color)
        c.circle(center: CGPoint(x: neck.x + 0.5, y: neck.y + 1.5), radius: 1.6, color)
        c.roundRect(CGRect(x: neck.x + 0.3, y: neck.y + 1.2, width: 1.9, height: 0.8), radius: 0.4, fill: .white)
        limb([CGPoint(x: neck.x - 0.2, y: neck.y - 0.8), CGPoint(x: neck.x + 1.2 - s * 1.2, y: neck.y - 2.2), CGPoint(x: neck.x + 2.2 - s * 1.6, y: neck.y - 1.4)], 1.0, color)
    }

    /// Hovering patrol bot, 6pt wide, base at `y`.
    static func bot(_ c: Canvas, x: CGFloat, y: CGFloat, t: Double) {
        let bob = CGFloat(sin(t * 6 + Double(x) * 0.1)) * 0.5
        let r = CGRect(x: x, y: y + 1 + bob, width: 6, height: 5)
        Glow.radial(c, CGPoint(x: r.midX, y: y + 0.5), 4, Pal.magenta, alpha: 0.5)
        c.roundRect(r, radius: 2, fill: NSColor(hex: "#3a1a5a"))
        c.roundRect(CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), radius: 2, fill: NSColor(hex: "#6a3a9a"))
        c.roundRect(CGRect(x: r.minX + 0.6, y: r.minY + 2, width: 4, height: 1.5), radius: 0.7, fill: NSColor(hex: "#0a0216"))
        let blink = Int(t * 3 + Double(x)) % 7 == 0
        if !blink { c.fill(CGRect(x: r.minX + 1 + CGFloat(sin(t * 2)) * 0.8, y: r.minY + 2.3, width: 1.6, height: 0.9), Pal.magenta) }
        c.line(from: CGPoint(x: r.midX + 1, y: r.maxY), to: CGPoint(x: r.midX + 1.6, y: r.maxY + 1.4), NSColor(white: 0.8, alpha: 1), width: 0.4)
        c.circle(center: CGPoint(x: r.midX + 1.6, y: r.maxY + 1.5), radius: 0.5, Int(t * 4) % 2 == 0 ? Pal.cyan : Pal.magenta)
    }
}
