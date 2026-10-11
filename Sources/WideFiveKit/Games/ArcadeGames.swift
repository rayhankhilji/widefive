import AppKit

/// Shared chrome for the small arcade games.
enum Arcade {
    static func banner(_ c: Canvas, _ title: String, _ sub: String, accent: NSColor, width: CGFloat = 520) {
        let r = CGRect(x: (c.width - width) / 2, y: 1, width: width, height: 28)
        c.roundRect(r, radius: 8, fill: NSColor(white: 0, alpha: 0.78), stroke: accent, lineWidth: 1)
        c.text(title, x: r.midX, y: 14, size: 11, color: accent, weight: .heavy, align: .center)
        c.text(sub, x: r.midX, y: 3, size: 8, color: .white, align: .center, maxWidth: width - 16)
    }
    static func score(_ c: Canvas, _ s: String, _ best: String, color: NSColor) {
        c.text(s, x: c.width - 8, y: 17, size: 10, color: .white, weight: .heavy, mono: true, align: .right)
        c.text(best, x: c.width - 8, y: 6, size: 7, color: color, mono: true, align: .right)
    }
}

/// Snake across the full length of the strip. ◀ ▶ turn left/right relative to travel; up/down work too.
public final class SnakeGame: StripMode {
    public let id = "snake"
    public let title = "Snake"
    public let icon = "scribble"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private let cell: CGFloat = 5
    private var cols = 200
    private let rows = 6
    private enum State { case title, playing, dead(Double) }
    private var state: State = .title
    private var snake: [(Int, Int)] = []
    private var dir = (1, 0)
    private var pendingDir = (1, 0)
    private var food = (40, 3)
    private var tick = 0.0
    private var speed = 0.09
    private var score = 0
    private var t = 0.0
    private var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    private func reset() {
        snake = (0..<6).map { (12 - $0, 2) }
        dir = (1, 0); pendingDir = dir; score = 0; speed = 0.09; tick = 0
        placeFood()
    }

    private func placeFood() {
        for _ in 0..<200 {
            let p = (3 + rng.next(cols - 6), rng.next(rows))
            if !snake.contains(where: { $0 == p }) { food = p; return }
        }
    }

    public func update(dt: Double) {
        t += dt
        guard case .playing = state else { return }
        tick += dt
        guard tick >= speed else { return }
        tick = 0
        dir = pendingDir
        var head = (snake[0].0 + dir.0, snake[0].1 + dir.1)
        if head.0 < 0 { head.0 = cols - 1 }; if head.0 >= cols { head.0 = 0 }
        if head.1 < 0 || head.1 >= rows || snake.contains(where: { $0 == head }) {
            state = .dead(t); HighScores.submit(id, score); return
        }
        snake.insert(head, at: 0)
        if head == food { score += 10; speed = max(0.035, speed * 0.985); placeFood() } else { snake.removeLast() }
    }

    private func turn(_ d: (Int, Int)) {
        if case .playing = state {
            if (d.0 + dir.0, d.1 + dir.1) != (0, 0) { pendingDir = d }
        } else { start() }
    }

    private func start() {
        if case .dead(let at) = state, t - at < 0.5 { return }
        reset(); state = .playing
    }

    public func draw(_ c: Canvas) {
        cols = Int(c.width / cell)
        c.gradient(c.bounds, [NSColor(hex: "#02160d"), NSColor(hex: "#04291a")])
        for x in stride(from: 0, to: c.width, by: cell * 4) { c.fill(CGRect(x: x, y: 0, width: 0.5, height: 30), NSColor(white: 1, alpha: 0.04)) }
        c.roundRect(CGRect(x: CGFloat(food.0) * cell + 0.5, y: CGFloat(food.1) * cell + 0.5, width: cell - 1, height: cell - 1), radius: 2, fill: Pal.red)
        for (i, s) in snake.enumerated() {
            let head = i == 0
            let shade = NSColor(hue: 0.38, saturation: 0.8, brightness: head ? 1 : 0.85 - CGFloat(i) / CGFloat(max(20, snake.count * 2)), alpha: 1)
            c.roundRect(CGRect(x: CGFloat(s.0) * cell + 0.3, y: CGFloat(s.1) * cell + 0.3, width: cell - 0.6, height: cell - 0.6), radius: head ? 2 : 1, fill: shade)
        }
        Arcade.score(c, "\(score)", "best \(HighScores.get(id))", color: Pal.lgreen)
        switch state {
        case .title: Arcade.banner(c, "SNAKE", "tap left / right half to steer · arrows work when keys are locked to the bar", accent: Pal.lgreen)
        case .dead: Arcade.banner(c, "DEAD · \(score)", "tap to play again · best \(HighScores.get(id))", accent: Pal.red)
        case .playing: break
        }
    }

    public func touchBegan(_ t: StripTouch) {
        guard case .playing = state else { start(); return }
        // Tap the half you want to turn toward; vertical turns come from the outer quarters.
        let f = t.x / max(1, ctxWidth)
        switch f {
        case ..<0.25: turn((0, 1))
        case ..<0.5: turn((-1, 0))
        case ..<0.75: turn((1, 0))
        default: turn((0, -1))
        }
    }

    private var ctxWidth: CGFloat { CGFloat(cols) * cell }

    public func keyDown(_ key: GameKey) {
        switch key {
        case .left: turn((-1, 0))
        case .right: turn((1, 0))
        case .up: turn((0, 1))
        case .down: turn((0, -1))
        case .jump, .action: start()
        default: break
        }
    }
}

/// Pong rotated for a long thin screen: paddles top and bottom, ball rallies between them.
public final class PongGame: StripMode {
    public let id = "pong"
    public let title = "Pong"
    public let icon = "circle.circle"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private enum State { case title, playing, over(Double) }
    private var state: State = .title
    private var ball = CGPoint(x: 300, y: 15)
    private var vel = CGPoint(x: 150, y: 70)
    private var player: CGFloat = 300
    private var ai: CGFloat = 300
    private var paddleW: CGFloat = 110
    private var you = 0, them = 0
    private var t = 0.0
    private var holding: CGFloat?

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    private func serve(toPlayer: Bool) {
        ball = CGPoint(x: player, y: 15)
        let angle = CGFloat.random(in: -0.6...0.6)
        vel = CGPoint(x: sin(angle) * 220, y: toPlayer ? -90 : 90)
    }

    public func update(dt: Double) {
        t += dt
        guard case .playing = state else { return }
        let dt = CGFloat(dt)
        ball.x += vel.x * dt
        ball.y += vel.y * dt
        if ball.x < 2 { ball.x = 2; vel.x = abs(vel.x) }
        if ball.x > width - 2 { ball.x = width - 2; vel.x = -abs(vel.x) }
        if let h = holding { player += (h - player) * min(1, 16 * dt) }
        player = max(paddleW / 2, min(width - paddleW / 2, player))
        // The AI is deliberately a bit lazy so rallies last.
        let aiSpeed: CGFloat = 170 + CGFloat(them + you) * 6
        ai += max(-aiSpeed * dt, min(aiSpeed * dt, ball.x - ai))
        ai = max(paddleW / 2, min(width - paddleW / 2, ai))
        if ball.y < 5, vel.y < 0 {
            if abs(ball.x - player) < paddleW / 2 + 3 {
                vel.y = abs(vel.y) * 1.03
                vel.x += (ball.x - player) * 3
                ball.y = 5
            } else if ball.y < -2 { them += 1; check(); serve(toPlayer: false) }
        }
        if ball.y > 25, vel.y > 0 {
            if abs(ball.x - ai) < paddleW / 2 + 3 {
                vel.y = -abs(vel.y) * 1.03
                vel.x += (ball.x - ai) * 2
                ball.y = 25
            } else if ball.y > 32 { you += 1; check(); serve(toPlayer: true) }
        }
        vel.x = max(-320, min(320, vel.x))
    }

    private func check() {
        if you >= 7 || them >= 7 {
            state = .over(t)
            if you > them { HighScores.submit(id, you * 10 - them) }
        }
    }

    private var width: CGFloat = 1085

    public func draw(_ c: Canvas) {
        width = c.width
        c.clear(NSColor(hex: "#050505"))
        for x in stride(from: 0, to: c.width, by: 16) { c.fill(CGRect(x: x, y: 14.6, width: 8, height: 0.8), NSColor(white: 1, alpha: 0.18)) }
        c.roundRect(CGRect(x: player - paddleW / 2, y: 0.5, width: paddleW, height: 3.5), radius: 1.75, fill: Pal.cyan)
        c.roundRect(CGRect(x: ai - paddleW / 2, y: 26, width: paddleW, height: 3.5), radius: 1.75, fill: Pal.magenta)
        c.circle(center: ball, radius: 2.4, .white)
        c.text("\(you)", x: 12, y: 2, size: 14, color: Pal.cyan, weight: .heavy, mono: true)
        c.text("\(them)", x: 12, y: 16, size: 14, color: Pal.magenta, weight: .heavy, mono: true)
        switch state {
        case .title: Arcade.banner(c, "PONG", "slide your finger to move the bottom paddle · first to 7", accent: Pal.cyan)
        case .over: Arcade.banner(c, you > them ? "YOU WIN \(you)–\(them)" : "YOU LOSE \(you)–\(them)", "tap to rematch", accent: you > them ? Pal.cyan : Pal.magenta)
        case .playing: break
        }
    }

    private func begin() {
        if case .over(let at) = state, t - at < 0.5 { return }
        you = 0; them = 0; serve(toPlayer: true); state = .playing
    }

    public func touchBegan(_ t: StripTouch) {
        if case .playing = state { holding = t.x; player = t.x } else { begin() }
    }
    public func touchMoved(_ t: StripTouch) { holding = t.x }
    public func touchEnded(_ t: StripTouch) { holding = nil }
    public func keyDown(_ key: GameKey) {
        switch key {
        case .left: holding = player - 90
        case .right: holding = player + 90
        default: begin()
        }
    }
    public func keyUp(_ key: GameKey) { holding = nil }
}

/// Breakout with a very wide, very short field: two rows of bricks, one paddle, one ball.
public final class BreakoutGame: StripMode {
    public let id = "breakout"
    public let title = "Breakout"
    public let icon = "rectangle.grid.3x2"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Brick { var rect: CGRect; var hue: CGFloat; var alive = true }
    private enum State { case title, playing, over(Double), won(Double) }
    private var state: State = .title
    private var bricks: [Brick] = []
    private var ball = CGPoint(x: 300, y: 10)
    private var vel = CGPoint(x: 160, y: 110)
    private var paddle: CGFloat = 300
    private let paddleW: CGFloat = 96
    private var lives = 3, score = 0
    private var width: CGFloat = 1085
    private var t = 0.0

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    private func build() {
        bricks = []
        let cols = Int((width - 20) / 26)
        for row in 0..<2 {
            for i in 0..<cols {
                let r = CGRect(x: 10 + CGFloat(i) * 26, y: 22 + CGFloat(row) * 4.5, width: 24, height: 4)
                bricks.append(Brick(rect: r, hue: CGFloat(i) / CGFloat(cols)))
            }
        }
        score = 0; lives = 3
        launch()
    }

    private func launch() {
        ball = CGPoint(x: paddle, y: 8)
        vel = CGPoint(x: CGFloat.random(in: -140...140), y: 130)
    }

    public func update(dt: Double) {
        t += dt
        guard case .playing = state else { return }
        let dt = CGFloat(dt)
        ball.x += vel.x * dt; ball.y += vel.y * dt
        if ball.x < 2 { ball.x = 2; vel.x = abs(vel.x) }
        if ball.x > width - 2 { ball.x = width - 2; vel.x = -abs(vel.x) }
        if ball.y > 29 { ball.y = 29; vel.y = -abs(vel.y) }
        if ball.y < 5.5, vel.y < 0, abs(ball.x - paddle) < paddleW / 2 + 2 {
            vel.y = abs(vel.y) * 1.02
            vel.x += (ball.x - paddle) * 3.2
            ball.y = 5.5
        }
        if ball.y < -2 {
            lives -= 1
            if lives <= 0 { state = .over(t); HighScores.submit(id, score) } else { launch() }
        }
        for i in bricks.indices where bricks[i].alive {
            guard bricks[i].rect.insetBy(dx: -2, dy: -2).contains(ball) else { continue }
            bricks[i].alive = false
            score += 25
            let r = bricks[i].rect
            if ball.x < r.minX || ball.x > r.maxX { vel.x = -vel.x } else { vel.y = -vel.y }
            break
        }
        if !bricks.contains(where: { $0.alive }) { state = .won(t); HighScores.submit(id, score + lives * 100) }
        vel.x = max(-280, min(280, vel.x))
    }

    public func draw(_ c: Canvas) {
        if abs(width - c.width) > 1 { width = c.width; if bricks.isEmpty { build() } }
        c.gradient(c.bounds, [NSColor(hex: "#0a0018"), NSColor(hex: "#1b0030")])
        for b in bricks where b.alive {
            c.roundRect(b.rect, radius: 1.5, fill: NSColor.hsb(b.hue + CGFloat(t) * 0.03, 0.75, 0.95))
        }
        c.roundRect(CGRect(x: paddle - paddleW / 2, y: 1, width: paddleW, height: 4), radius: 2, fill: Pal.cyan)
        c.circle(center: ball, radius: 2.2, .white)
        Arcade.score(c, "\(score)  ♥\(lives)", "best \(HighScores.get(id))", color: Pal.cyan)
        switch state {
        case .title: Arcade.banner(c, "BREAKOUT", "slide to move the paddle · clear both rows", accent: Pal.cyan)
        case .over: Arcade.banner(c, "GAME OVER · \(score)", "tap to retry", accent: Pal.red)
        case .won: Arcade.banner(c, "CLEARED · \(score)", "tap for a fresh wall", accent: Pal.yellow)
        case .playing: break
        }
    }

    private func begin() {
        if case .over(let a) = state, t - a < 0.5 { return }
        if case .won(let a) = state, t - a < 0.5 { return }
        build(); state = .playing
    }

    public func touchBegan(_ t: StripTouch) { if case .playing = state { paddle = t.x } else { begin() } }
    public func touchMoved(_ t: StripTouch) { paddle = max(paddleW / 2, min(width - paddleW / 2, t.x)) }
    public func keyDown(_ key: GameKey) {
        switch key {
        case .left: paddle = max(paddleW / 2, paddle - 40)
        case .right: paddle = min(width - paddleW / 2, paddle + 40)
        default: begin()
        }
    }
}

/// Flappy-style: tap to flap through the gaps. Brutal on a 30pt-tall screen, which is the point.
public final class FlappyGame: StripMode {
    public let id = "flappy"
    public let title = "Flap"
    public let icon = "bird.fill"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Pipe { var x: CGFloat; var gapY: CGFloat; var scored = false }
    private enum State { case title, playing, dead(Double) }
    private var state: State = .title
    private var y: CGFloat = 15
    private var vy: CGFloat = 0
    private var pipes: [Pipe] = []
    private var scroll: CGFloat = 150
    private var score = 0
    private var t = 0.0
    private var width: CGFloat = 1085
    private let gap: CGFloat = 13
    private let particles = Particles()

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    private func reset() {
        y = 15; vy = 0; score = 0; scroll = 150
        pipes = (0..<6).map { Pipe(x: 300 + CGFloat($0) * 190, gapY: CGFloat.random(in: 9...21)) }
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt))
        guard case .playing = state else { return }
        let dt = CGFloat(dt)
        scroll = min(300, scroll + dt * 4)
        vy -= 460 * dt
        y += vy * dt
        if y < 3 || y > 28 { die(); return }
        for i in pipes.indices {
            pipes[i].x -= scroll * dt
            if pipes[i].x < -20 {
                pipes[i].x += CGFloat(pipes.count) * 190
                pipes[i].gapY = CGFloat.random(in: 9...21)
                pipes[i].scored = false
            }
            let p = pipes[i]
            if abs(p.x - 90) < 10, abs(y - p.gapY) > gap / 2 { die(); return }
            if !pipes[i].scored, p.x < 86 { pipes[i].scored = true; score += 1 }
        }
    }

    private func die() {
        state = .dead(t)
        HighScores.submit(id, score)
        particles.burst(x: 90, y: y, count: 20, colors: [Pal.yellow, Pal.orange, .white], speed: 70, life: 0.8)
    }

    private func flap() {
        switch state {
        case .playing:
            vy = 115
            particles.burst(x: 86, y: y - 2, count: 3, colors: [.white], speed: 20, life: 0.2, size: 1)
        case .dead(let at): if t - at > 0.5 { reset(); state = .playing }
        case .title: reset(); state = .playing
        }
    }

    public func draw(_ c: Canvas) {
        width = c.width
        c.gradient(c.bounds, [NSColor(hex: "#4ec0ca"), NSColor(hex: "#9be7d8")])
        c.fill(CGRect(x: 0, y: 0, width: c.width, height: 3), NSColor(hex: "#ded895"))
        for p in pipes {
            let col = NSColor(hex: "#5bbf3a")
            c.roundRect(CGRect(x: p.x, y: 0, width: 18, height: p.gapY - gap / 2), radius: 2, fill: col, stroke: NSColor(hex: "#2f7a1c"), lineWidth: 0.8)
            c.roundRect(CGRect(x: p.x, y: p.gapY + gap / 2, width: 18, height: 30 - (p.gapY + gap / 2)), radius: 2, fill: col, stroke: NSColor(hex: "#2f7a1c"), lineWidth: 0.8)
        }
        if case .dead = state {} else {
            c.cg.saveGState()
            c.cg.translateBy(x: 90, y: y)
            c.cg.rotate(by: max(-0.6, min(0.5, vy / 220)))
            c.sprite(Sprites.bird, x: -4, y: -3, scale: 1, flipX: false)
            c.cg.restoreGState()
        }
        particles.draw(c, camX: 0)
        Arcade.score(c, "\(score)", "best \(HighScores.get(id))", color: NSColor(hex: "#2f7a1c"))
        switch state {
        case .title: Arcade.banner(c, "FLAP", "tap anywhere to flap · thread the gaps", accent: Pal.yellow)
        case .dead: Arcade.banner(c, "SPLAT · \(score)", "tap to try again · best \(HighScores.get(id))", accent: Pal.red)
        case .playing: break
        }
    }

    public func touchBegan(_ t: StripTouch) { flap() }
    public func keyDown(_ key: GameKey) { if key == .jump || key == .up || key == .action { flap() } }
}

/// Side-scrolling shooter: hold the left pad to move up/down, A to fire, waves of ships come at you.
public final class ShooterGame: StripMode {
    public let id = "shooter"
    public let title = "Starstrip"
    public let icon = "airplane"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Foe { var p: CGPoint; var vy: CGFloat; var hp: Int; var kind: Int }
    private enum State { case title, playing, dead(Double) }
    private var state: State = .title
    private var ship = CGPoint(x: 60, y: 15)
    private var shots: [CGPoint] = []
    private var foeShots: [CGPoint] = []
    private var foes: [Foe] = []
    private let controls = PadControls()
    private var cool = 0.0, spawn = 0.0, level = 1.0
    private var score = 0, lives = 3
    private var t = 0.0
    private var width: CGFloat = 1085
    private let particles = Particles()

    public init() {}
    public func activate(_ ctx: ModeContext) { controls.reset() }

    private func reset() {
        ship = CGPoint(x: 60, y: 15); shots = []; foeShots = []; foes = []
        score = 0; lives = 3; level = 1; spawn = 0
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt))
        guard case .playing = state else {
            if controls.jumpPressed { controls.jumpPressed = false; begin() }
            return
        }
        let dt = CGFloat(dt)
        level += Double(dt) * 0.05
        // The left pad doubles as up/down here.
        if controls.left { ship.y -= 60 * dt }
        if controls.right { ship.y += 60 * dt }
        ship.y = max(4, min(26, ship.y))
        cool -= Double(dt)
        if (controls.jump || controls.run), cool <= 0 { shots.append(CGPoint(x: ship.x + 8, y: ship.y)); cool = 0.14 }
        controls.jumpPressed = false
        shots = shots.compactMap { var s = $0; s.x += 420 * dt; return s.x < width ? s : nil }
        foeShots = foeShots.compactMap { var s = $0; s.x -= 190 * dt; return s.x > 0 ? s : nil }
        spawn -= Double(dt)
        if spawn <= 0 {
            spawn = max(0.25, 1.1 - level * 0.05)
            let kind = Int.random(in: 0...2)
            foes.append(Foe(p: CGPoint(x: width + 10, y: CGFloat.random(in: 5...25)), vy: CGFloat.random(in: -14...14), hp: kind == 2 ? 3 : 1, kind: kind))
        }
        for i in foes.indices.reversed() {
            var f = foes[i]
            f.p.x -= (70 + CGFloat(level) * 6) * dt
            f.p.y += f.vy * dt
            if f.p.y < 4 || f.p.y > 26 { f.vy = -f.vy }
            if f.kind == 1, Double.random(in: 0...1) < Double(dt) * 0.6 { foeShots.append(f.p) }
            if f.p.x < -10 { foes.remove(at: i); continue }
            if abs(f.p.x - ship.x) < 6, abs(f.p.y - ship.y) < 5 { foes.remove(at: i); hit(); continue }
            var killed = false
            for j in shots.indices.reversed() where abs(shots[j].x - f.p.x) < 6 && abs(shots[j].y - f.p.y) < 4 {
                shots.remove(at: j)
                f.hp -= 1
                if f.hp <= 0 {
                    killed = true; score += f.kind == 2 ? 300 : 100
                    particles.burst(x: f.p.x, y: f.p.y, count: 12, colors: [Pal.orange, Pal.yellow, .white], speed: 60, life: 0.5, gravity: 0)
                }
                break
            }
            if killed { foes.remove(at: i) } else { foes[i] = f }
        }
        for j in foeShots.indices.reversed() where abs(foeShots[j].x - ship.x) < 5 && abs(foeShots[j].y - ship.y) < 4 {
            foeShots.remove(at: j); hit()
        }
    }

    private func hit() {
        lives -= 1
        particles.burst(x: ship.x, y: ship.y, count: 16, colors: [Pal.red, Pal.yellow, .white], speed: 70, life: 0.6, gravity: 0)
        if lives <= 0 { state = .dead(t); HighScores.submit(id, score) } else { ship = CGPoint(x: 60, y: 15) }
    }

    private func begin() {
        if case .dead(let a) = state, t - a < 0.5 { return }
        reset(); state = .playing
    }

    public func draw(_ c: Canvas) {
        width = c.width
        controls.width = c.width
        c.gradient(c.bounds, [NSColor(hex: "#01010f"), NSColor(hex: "#0b0030")])
        for i in 0..<80 {
            let x = (CGFloat(i * 97) - CGFloat(t) * (40 + CGFloat(i % 3) * 30)).truncatingRemainder(dividingBy: c.width)
            c.fill(CGRect(x: x < 0 ? x + c.width : x, y: CGFloat((i * 29) % 30), width: 1.5, height: 0.8), NSColor(white: 1, alpha: 0.5))
        }
        for s in shots { c.fill(CGRect(x: s.x, y: s.y - 0.5, width: 6, height: 1.4), Pal.cyan) }
        for s in foeShots { c.fill(CGRect(x: s.x, y: s.y - 0.5, width: 5, height: 1.4), Pal.magenta) }
        for f in foes {
            let tint: NSColor = f.kind == 2 ? Pal.magenta : (f.kind == 1 ? Pal.orange : Pal.grey)
            c.sprite(Sprites.foe, x: f.p.x - 4, y: f.p.y - 3, tint: tint)
        }
        if case .dead = state {} else { c.sprite(Sprites.ship, x: ship.x - 5, y: ship.y - 3) }
        particles.draw(c, camX: 0)
        Arcade.score(c, "\(score)  ♥\(lives)", "best \(HighScores.get(id))", color: Pal.cyan)
        controls.draw(c)
        switch state {
        case .title: Arcade.banner(c, "STARSTRIP", "◀ ▶ pad = up/down · A = fire · survive the waves", accent: Pal.cyan)
        case .dead: Arcade.banner(c, "DESTROYED · \(score)", "press A to fly again", accent: Pal.red)
        case .playing: break
        }
    }

    public func touchBegan(_ t: StripTouch) { if !controls.began(t) { if case .playing = state {} else { begin() } } }
    public func touchMoved(_ t: StripTouch) { controls.moved(t) }
    public func touchEnded(_ t: StripTouch) { controls.ended(t) }
    public func keyDown(_ key: GameKey) {
        controls.key(key == .up ? .left : (key == .down ? .right : key), down: true)
        if case .playing = state {} else { begin() }
    }
    public func keyUp(_ key: GameKey) { controls.key(key == .up ? .left : (key == .down ? .right : key), down: false) }
}
