import AppKit

/// Shared chrome for every game: glass panels, italic display type, keycap hints, eased title / game-over cards and HUD pills.
enum Arcade {
    static let ink = NSColor(hex: "#0a0814")

    /// Static banner (kept for other games, e.g. the racer). Same look as the animated cards.
    static func banner(_ c: Canvas, _ title: String, _ sub: String, accent: NSColor, width: CGFloat = 520) {
        let r = CGRect(x: (c.width - width) / 2, y: 2, width: width, height: 26)
        panel(c, r, accent: accent)
        display(c, title, x: r.midX, y: 12.5, size: 11, color: accent, align: .center)
        c.text(sub, x: r.midX, y: 3.5, size: 7.5, color: NSColor(white: 0.9, alpha: 1), weight: .semibold, align: .center, maxWidth: width - 16)
    }

    /// Dark glass panel with an accent rim, top sheen and soft drop shadow.
    static func panel(_ c: Canvas, _ r: CGRect, accent: NSColor, radius: CGFloat = 8) {
        c.roundRect(r.offsetBy(dx: 0, dy: -1).insetBy(dx: -1, dy: -0.5), radius: radius + 1, fill: NSColor(white: 0, alpha: 0.35))
        c.gradient(r, [NSColor(hex: "#1c1830", alpha: 0.94), NSColor(hex: "#07060f", alpha: 0.94)], radius: radius)
        c.gradient(CGRect(x: r.minX + 2, y: r.midY, width: r.width - 4, height: r.height / 2 - 1),
                   [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0.0)], radius: radius - 1)
        c.roundRect(r, radius: radius, fill: .clear, stroke: accent.withAlphaComponent(0.85), lineWidth: 0.8)
        c.fill(CGRect(x: r.minX + radius, y: r.minY + 0.4, width: r.width - radius * 2, height: 0.5), accent.withAlphaComponent(0.35))
    }

    /// Heavy italic display type with a drop shadow and a faint glow.
    @discardableResult
    static func display(_ c: Canvas, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, align: NSTextAlignment = .left,
                        shadow: NSColor = NSColor(white: 0, alpha: 0.75), skew: CGFloat = 0.18) -> CGFloat {
        let w = Canvas.measure(s, size: size, weight: .black)
        let ox: CGFloat = align == .center ? -w / 2 : (align == .right ? -w : 0)
        c.cg.saveGState()
        c.cg.translateBy(x: x + ox, y: y)
        c.cg.concatenate(CGAffineTransform(a: 1, b: 0, c: skew, d: 1, tx: 0, ty: 0))
        c.text(s, x: 0.7, y: -0.8, size: size, color: shadow, weight: .black)
        c.text(s, x: 0, y: 0, size: size, color: color, weight: .black)
        c.cg.restoreGState()
        return w
    }

    /// A keycap chip ("A", "SPACE", "←→"); returns its width.
    @discardableResult
    static func keycap(_ c: Canvas, _ label: String, x: CGFloat, y: CGFloat, h: CGFloat = 10) -> CGFloat {
        let w = max(h, Canvas.measure(label, size: 6.5, weight: .heavy) + 5)
        let r = CGRect(x: x, y: y, width: w, height: h)
        c.roundRect(r.offsetBy(dx: 0, dy: -0.8), radius: 2.2, fill: NSColor(white: 0.45, alpha: 1))
        c.roundRect(r, radius: 2.2, fill: NSColor(white: 0.93, alpha: 1))
        c.text(label, x: r.midX, y: y + h / 2 - 4.6, size: 6.5, color: NSColor(white: 0.12, alpha: 1), weight: .heavy, align: .center)
        return w
    }

    /// Row of (keys, label) hints; keys separated by spaces become separate caps. Returns the total width.
    @discardableResult
    static func hints(_ c: Canvas, _ items: [(String, String)], x: CGFloat, y: CGFloat, measureOnly: Bool = false) -> CGFloat {
        var cx = x
        for (i, (keys, label)) in items.enumerated() {
            for k in keys.split(separator: " ") {
                let kw = max(10, Canvas.measure(String(k), size: 6.5, weight: .heavy) + 5)
                if !measureOnly { keycap(c, String(k), x: cx, y: y) }
                cx += kw + 1.5
            }
            let lw = Canvas.measure(label, size: 7, weight: .semibold)
            if !measureOnly { c.text(label, x: cx + 1, y: y + 0.6, size: 7, color: NSColor(white: 0.82, alpha: 1), weight: .semibold) }
            cx += lw + (i == items.count - 1 ? 1 : 9)
        }
        return cx - x
    }

    /// Animated title card. `age` = seconds since the card appeared (drives the slide-in, sheen and prompt pulse).
    static func titleCard(_ c: Canvas, age: Double, title: String, tagline: String, accent: NSColor, accent2: NSColor,
                          hints items: [(String, String)], best: Int?, prompt: String = "PRESS A / TAP") {
        let titleW = max(Canvas.measure(title, size: 14, weight: .black) + 6, Canvas.measure(tagline, size: 6.5, weight: .semibold))
        let hintW = hints(c, items, x: 0, y: 0, measureOnly: true)
        let bestW: CGFloat = best == nil ? 0 : 46
        let promptW = Canvas.measure(prompt, size: 7, weight: .heavy) + 18
        let w = 14 + titleW + 12 + hintW + 12 + bestW + promptW + 8
        cardFrame(c, age: age, width: w, accent: accent, accent2: accent2) { r in
            var x = r.minX + 12
            display(c, title, x: x, y: 10, size: 14, color: accent)
            c.text(tagline.uppercased(), x: x + 1, y: 3.2, size: 6.5, color: accent2.withAlphaComponent(0.9), weight: .bold)
            x += titleW + 6
            divider(c, x, r); x += 6
            hints(c, items, x: x, y: r.midY - 5)
            x += hintW + 6
            if let best {
                divider(c, x, r); x += 6
                c.text("BEST", x: x + 20, y: 15, size: 5.5, color: NSColor(white: 0.6, alpha: 1), weight: .heavy, align: .center)
                c.text("\(best)", x: x + 20, y: 5, size: 9, color: .white, weight: .heavy, mono: true, align: .center)
                x += bestW
            }
            promptPill(c, prompt, CGRect(x: r.maxX - promptW - 4, y: r.minY + 4, width: promptW, height: r.height - 8), accent: accent, age: age)
        }
    }

    /// Animated game-over card: title punches in, score counts up, NEW BEST badge pops.
    static func overCard(_ c: Canvas, age: Double, title: String, score: Int, best: Int, newBest: Bool, accent: NSColor,
                         stats: String = "", prompt: String = "PRESS A / TAP") {
        let titleW = Canvas.measure(title, size: 14, weight: .black) + 8
        let statsW = stats.isEmpty ? 0 : Canvas.measure(stats, size: 7, weight: .semibold) + 14
        let promptW = Canvas.measure(prompt, size: 7, weight: .heavy) + 18
        let w = 14 + titleW + 12 + 70 + 56 + statsW + promptW + (newBest ? 46 : 0) + 6
        cardFrame(c, age: age, width: w, accent: accent, accent2: accent) { r in
            var x = r.minX + 12
            let punch = 1 + 0.35 * (1 - Ease.outBack(age / 0.35, 3))
            c.cg.saveGState()
            c.cg.translateBy(x: x + titleW / 2, y: r.midY)
            c.cg.scaleBy(x: CGFloat(punch), y: CGFloat(punch))
            display(c, title, x: -titleW / 2 + 2, y: -6.5, size: 14, color: accent)
            c.cg.restoreGState()
            x += titleW + 6
            divider(c, x, r); x += 6
            let shown = Int(Double(score) * Ease.outCubic((age - 0.25) / 0.9))
            c.text("SCORE", x: x + 2, y: 15.5, size: 5.5, color: NSColor(white: 0.6, alpha: 1), weight: .heavy)
            c.text("\(shown)", x: x + 2, y: 4, size: 11, color: .white, weight: .black, mono: true)
            x += 70
            c.text("BEST", x: x, y: 15.5, size: 5.5, color: NSColor(white: 0.6, alpha: 1), weight: .heavy)
            c.text("\(max(best, score))", x: x, y: 5, size: 8.5, color: NSColor(white: 0.85, alpha: 1), weight: .heavy, mono: true)
            x += 56
            if newBest {
                let k = Ease.outBack((age - 1.1) / 0.4, 2.5)
                if k > 0 {
                    c.cg.saveGState()
                    c.cg.translateBy(x: x + 19, y: r.midY)
                    c.cg.rotate(by: CGFloat(-0.12 + 0.05 * sin(age * 6)))
                    c.cg.scaleBy(x: CGFloat(k), y: CGFloat(k))
                    Icons.star(c, .zero, 13, NSColor(hex: "#ffd23f"), points: 10, inner: 0.78, rotation: CGFloat(age))
                    c.text("NEW", x: 0, y: 0.3, size: 5.5, color: NSColor(hex: "#3a1d00"), weight: .black, align: .center)
                    c.text("BEST", x: 0, y: -5.6, size: 5.5, color: NSColor(hex: "#3a1d00"), weight: .black, align: .center)
                    c.cg.restoreGState()
                }
                x += 46
            }
            if !stats.isEmpty {
                divider(c, x, r); x += 6
                c.text(stats, x: x, y: r.midY - 4.5, size: 7, color: NSColor(white: 0.8, alpha: 1), weight: .semibold)
            }
            if age > 0.6 {
                promptPill(c, prompt, CGRect(x: r.maxX - promptW - 4, y: r.minY + 4, width: promptW, height: r.height - 8), accent: accent, age: age)
            }
        }
    }

    private static func divider(_ c: Canvas, _ x: CGFloat, _ r: CGRect) {
        c.fill(CGRect(x: x, y: r.minY + 5, width: 0.6, height: r.height - 10), NSColor(white: 1, alpha: 0.14))
    }

    private static func promptPill(_ c: Canvas, _ s: String, _ r: CGRect, accent: NSColor, age: Double) {
        let pulse = CGFloat(0.5 + 0.5 * sin(age * 4.5))
        Glow.radial(c, CGPoint(x: r.midX, y: r.midY), r.width * 0.6, accent, alpha: 0.18 + 0.2 * pulse)
        c.roundRect(r, radius: r.height / 2, fill: accent.withAlphaComponent(0.78 + 0.22 * pulse))
        c.polygon([CGPoint(x: r.minX + 6, y: r.midY + 2.6), CGPoint(x: r.minX + 6, y: r.midY - 2.6), CGPoint(x: r.minX + 10, y: r.midY)], ink)
        c.text(s, x: r.minX + 12.5, y: r.midY - 4.6, size: 7, color: ink, weight: .heavy)
    }

    /// Slides the card up with overshoot, fades it in, and sweeps a sheen across it every few seconds.
    private static func cardFrame(_ c: Canvas, age: Double, width w: CGFloat, accent: NSColor, accent2: NSColor, _ body: (CGRect) -> Void) {
        let k = CGFloat(Ease.outBack(age / 0.45, 1.4))
        let a = CGFloat(Ease.outCubic(age / 0.25))
        let cx = (c.width + StripController.gameChromeWidth) / 2
        let r = CGRect(x: cx - w / 2, y: 2 - (1 - k) * 26, width: w, height: 26)
        c.cg.saveGState()
        c.cg.setAlpha(a)
        c.cg.beginTransparencyLayer(auxiliaryInfo: nil)
        panel(c, r, accent: accent)
        c.gradient(CGRect(x: r.minX, y: r.minY, width: 3, height: r.height), [accent, accent2], radius: 1.5)
        body(r)
        let sweep = (age.truncatingRemainder(dividingBy: 3.2) - 0.4) / 0.9
        if sweep > 0, sweep < 1 {
            c.clip(r) {
                let sx = r.minX - 40 + (r.width + 80) * CGFloat(sweep)
                c.polygon([CGPoint(x: sx, y: r.minY), CGPoint(x: sx + 18, y: r.minY), CGPoint(x: sx + 30, y: r.maxY), CGPoint(x: sx + 12, y: r.maxY)],
                          NSColor(white: 1, alpha: 0.07))
            }
        }
        c.cg.endTransparencyLayer()
        c.cg.restoreGState()
    }

    struct HUDItem {
        var label: String
        var value: String
        var color: NSColor = .white
        var hearts: Int? = nil
        init(_ label: String, _ value: String, color: NSColor = .white) { self.label = label; self.value = value; self.color = color }
        init(lives: Int, color: NSColor = NSColor(hex: "#ff4d6d")) { label = "LIVES"; value = ""; hearts = lives; self.color = color }
    }

    /// Right-aligned HUD pill. `pulse` (0…1, decaying) bumps the first value after scoring.
    static func hud(_ c: Canvas, _ items: [HUDItem], accent: NSColor, pulse: CGFloat = 0, right: CGFloat? = nil) {
        var widths: [CGFloat] = []
        for it in items {
            if let h = it.hearts { widths.append(max(22, CGFloat(min(h, 5)) * 7 + 2)) } else {
                widths.append(max(Canvas.measure(it.label, size: 5.5, weight: .heavy), Canvas.measure(it.value, size: 9.5, weight: .heavy, mono: true)) + 2)
            }
        }
        let total = widths.reduce(0, +) + CGFloat(items.count - 1) * 10 + 14
        let r = CGRect(x: (right ?? c.width - 4) - total, y: 3, width: total, height: 24)
        c.roundRect(r, radius: 8, fill: NSColor(hex: "#06050c", alpha: 0.72), stroke: accent.withAlphaComponent(0.35), lineWidth: 0.6)
        var x = r.minX + 7
        for (i, it) in items.enumerated() {
            c.text(it.label, x: x, y: 16, size: 5.5, color: accent.withAlphaComponent(0.9), weight: .heavy)
            if let h = it.hearts {
                for k in 0..<min(h, 5) { Icons.heart(c, CGPoint(x: x + 3.5 + CGFloat(k) * 7, y: 9.5), 6, it.color) }
                if h > 5 { c.text("+\(h - 5)", x: x + 36, y: 6, size: 6, color: it.color, weight: .heavy) }
            } else if i == 0 && pulse > 0.01 {
                c.cg.saveGState()
                let s = 1 + 0.3 * pulse
                c.cg.translateBy(x: x, y: 9); c.cg.scaleBy(x: s, y: s)
                c.text(it.value, x: 0, y: -4.5, size: 9.5, color: it.color.blended(withFraction: pulse, of: NSColor(hex: "#ffd23f")) ?? it.color, weight: .heavy, mono: true)
                c.cg.restoreGState()
            } else {
                c.text(it.value, x: x, y: 4.5, size: 9.5, color: it.color, weight: .heavy, mono: true)
            }
            x += widths[i] + 10
        }
    }

    /// Floating "+100" style popups.
    struct Popup { var x: CGFloat, y: CGFloat, text: String, color: NSColor, age: Double = 0, life: Double = 0.8 }
    static func update(_ pops: inout [Popup], _ dt: Double) {
        for i in pops.indices { pops[i].age += dt }
        pops.removeAll { $0.age >= $0.life }
    }
    static func draw(_ c: Canvas, _ pops: [Popup], camX: CGFloat = 0) {
        for p in pops {
            let k = p.age / p.life
            let s = CGFloat(Ease.outBack(min(1, p.age / 0.18), 3))
            let a = CGFloat(1 - Ease.inCubic(k))
            c.cg.saveGState()
            c.cg.translateBy(x: p.x - camX, y: p.y + CGFloat(Ease.outCubic(k)) * 7)
            c.cg.scaleBy(x: s, y: s)
            c.text(p.text, x: 0.5, y: -0.5, size: 6.5, color: NSColor(white: 0, alpha: 0.6 * a), weight: .black, align: .center)
            c.text(p.text, x: 0, y: 0, size: 6.5, color: p.color.withAlphaComponent(a), weight: .black, align: .center)
            c.cg.restoreGState()
        }
    }
}

/// Snake across the full length of the strip, with smooth interpolated movement, golden fruit and a greedy demo bot.
public final class SnakeGame: StripMode, DemoStartable {
    public let id = "snake"
    public let title = "Snake"
    public let icon = "scribble"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private let cell: CGFloat = 5
    private var cols = 200
    private let rows = 6
    private enum State { case title, playing, dead }
    private var state: State = .title
    private var stateT = 0.0
    private var snake: [(Int, Int)] = []
    private var prev: [(Int, Int)] = []
    private var dir = (1, 0)
    private var queued: [(Int, Int)] = []
    private var food = (40, 3)
    private var golden: (Int, Int)? = nil
    private var goldenUntil = 0.0
    private var eaten = 0
    private var bulges: [Int] = []
    private var tick = 0.0
    private var speed = 0.1
    private var score = 0
    private var newBest = false
    private var t = 0.0
    private var demo = false
    private var pulse: CGFloat = 0
    private let particles = Particles()
    private let shake = Shake(maxOffset: 2.5)
    private var pops: [Arcade.Popup] = []
    private var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))
    private var x0: CGFloat { StripController.gameChromeWidth + 4 }

    public init() {}
    public func activate(_ ctx: ModeContext) {}
    public func startDemo() { demo = true; reset(); state = .playing; stateT = t }

    private func reset() {
        snake = (0..<7).map { (14 - $0, 2) }
        prev = snake
        dir = (1, 0); queued = []; score = 0; speed = 0.1; tick = 0; eaten = 0; bulges = []; golden = nil; newBest = false
        placeFood()
    }

    private func free(_ p: (Int, Int)) -> Bool { !snake.contains { $0 == p } && p != food }
    private func placeFood() {
        for _ in 0..<300 {
            let p = (4 + rng.next(cols - 30), rng.next(rows))
            if free(p) { food = p; return }
        }
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt)); Arcade.update(&pops, dt)
        pulse = max(0, pulse - CGFloat(dt) * 3)
        if let _ = golden, t > goldenUntil { golden = nil }
        guard state == .playing else { return }
        tick += dt
        guard tick >= speed else { return }
        tick -= speed
        if demo { botSteer() }
        if !queued.isEmpty { dir = queued.removeFirst() }
        prev = snake
        var head = (snake[0].0 + dir.0, snake[0].1 + dir.1)
        if head.0 < 0 { head.0 = cols - 1 }; if head.0 >= cols { head.0 = 0 }
        if head.1 < 0 || head.1 >= rows || snake.dropLast().contains(where: { $0 == head }) { die(); return }
        snake.insert(head, at: 0)
        bulges = bulges.map { $0 + 1 }.filter { $0 < snake.count }
        let hx = x0 + (CGFloat(head.0) + 0.5) * cell, hy = (CGFloat(head.1) + 0.5) * cell
        if head == food {
            eaten += 1; score += 10; pulse = 1; bulges.append(0)
            speed = max(0.04, speed * 0.975)
            particles.burst(x: hx, y: hy, count: 14, colors: [NSColor(hex: "#ff5a5f"), NSColor(hex: "#ffd23f"), .white], speed: 55, life: 0.45, size: 1.4, gravity: -60, kind: .dot, drag: 3)
            particles.ring(x: hx, y: hy, color: NSColor(hex: "#ff8a8a"), radius: 9)
            pops.append(.init(x: hx, y: hy + 4, text: "+10", color: .white))
            placeFood()
            if eaten % 5 == 0 { spawnGolden() }
        } else if let g = golden, head == g {
            score += 50; pulse = 1; bulges.append(0); golden = nil
            particles.burst(x: hx, y: hy, count: 24, colors: [NSColor(hex: "#ffd23f"), NSColor(hex: "#fff3b0")], speed: 70, life: 0.6, size: 2.2, gravity: 0, kind: .sparkle, drag: 3)
            particles.ring(x: hx, y: hy, color: NSColor(hex: "#ffd23f"), radius: 14)
            pops.append(.init(x: hx, y: hy + 4, text: "+50 GOLD", color: NSColor(hex: "#ffd23f"), life: 1.1))
            shake.add(0.25)
        } else {
            snake.removeLast()
        }
    }

    private func spawnGolden() {
        for _ in 0..<100 {
            let p = (6 + rng.next(cols - 30), rng.next(rows))
            if free(p) { golden = p; goldenUntil = t + 6; return }
        }
    }

    private func die() {
        state = .dead; stateT = t
        newBest = HighScores.submit(id, score)
        shake.add(0.7)
        for (i, s) in snake.enumerated() where i % 2 == 0 {
            particles.burst(x: x0 + (CGFloat(s.0) + 0.5) * cell, y: (CGFloat(s.1) + 0.5) * cell, count: 2, colors: [NSColor(hex: "#3ddc84"), NSColor(hex: "#a6ff4d")],
                            speed: 50, life: 0.8, size: 1.8, gravity: -120, kind: .square)
        }
    }

    private func botSteer() {
        let h = snake[0]
        let target = golden ?? food
        let options = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { ($0.0 + dir.0, $0.1 + dir.1) != (0, 0) }
        func safe(_ d: (Int, Int)) -> Bool {
            let n = ((h.0 + d.0 + cols) % cols, h.1 + d.1)
            return n.1 >= 0 && n.1 < rows && !snake.dropLast().contains { $0 == n }
        }
        func dist(_ d: (Int, Int)) -> Int { abs(h.0 + d.0 - target.0) + abs(h.1 + d.1 - target.1) }
        if let best = options.filter(safe).min(by: { dist($0) < dist($1) }) { queued = [best] }
    }

    private func turn(_ d: (Int, Int)) {
        guard state == .playing else { start(); return }
        let last = queued.last ?? dir
        if (d.0 + last.0, d.1 + last.1) != (0, 0), d != last, queued.count < 2 { queued.append(d) }
    }

    private func start() {
        if state == .dead, t - stateT < 0.6 { return }
        demo = false
        reset(); state = .playing; stateT = t
    }

    private func segPos(_ i: Int, _ f: CGFloat) -> CGPoint {
        let cur = snake[i]
        let old = i < prev.count ? prev[i] : cur
        var dx = CGFloat(cur.0 - old.0)
        if abs(dx) > 1 { dx = 0 }
        let gx = CGFloat(cur.0) - dx * (1 - f), gy = CGFloat(old.1) + CGFloat(cur.1 - old.1) * f
        return CGPoint(x: x0 + (gx + 0.5) * cell, y: (gy + 0.5) * cell)
    }

    public func draw(_ c: Canvas) {
        cols = Int((c.width - x0 - 4) / cell)
        c.gradient(c.bounds, [NSColor(hex: "#06281c"), NSColor(hex: "#021009")])
        for col in 0..<cols { for r in 0..<rows where (col + r) % 2 == 0 {
            c.fill(CGRect(x: x0 + CGFloat(col) * cell, y: CGFloat(r) * cell, width: cell, height: cell), NSColor(white: 1, alpha: 0.025))
        } }
        for i in 0..<26 { // fireflies
            let fx = (CGFloat(i) * 173.3 + CGFloat(sin(t * 0.3 + Double(i))) * 30).truncatingRemainder(dividingBy: c.width)
            let fy = 15 + CGFloat(sin(t * 0.7 + Double(i) * 1.7)) * 12
            Glow.radial(c, CGPoint(x: fx, y: fy), 3, NSColor(hex: "#c6ff6b"), alpha: CGFloat(0.25 + 0.25 * sin(t * 2 + Double(i))))
        }
        c.cg.saveGState()
        shake.apply(c)
        drawFruit(c, food, gold: false)
        if let g = golden { drawFruit(c, g, gold: true) }
        if state != .title || !snake.isEmpty, !snake.isEmpty {
            let f = state == .playing ? CGFloat(min(1, tick / speed)) : 1
            let n = snake.count
            let fade: CGFloat = state == .dead ? CGFloat(max(0, 1 - (t - stateT) * 1.4)) : 1
            if fade > 0 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    let p = segPos(i, f)
                    let k = CGFloat(i) / CGFloat(max(1, n - 1))
                    var r = cell * (0.62 - 0.2 * k)
                    if bulges.contains(i) { r *= 1.35 }
                    let flash = state == .dead && Int((t - stateT) * 14) % 2 == 0
                    let base = flash ? NSColor.white : NSColor(hue: 0.36 - 0.08 * k, saturation: 0.85, brightness: 0.95 - 0.35 * k, alpha: fade)
                    c.circle(center: CGPoint(x: p.x, y: p.y - 0.4), radius: r, NSColor(white: 0, alpha: 0.25 * fade))
                    c.circle(center: p, radius: r, base)
                    if i % 2 == 0 { c.circle(center: CGPoint(x: p.x - r * 0.15, y: p.y + r * 0.35), radius: r * 0.42, NSColor(white: 1, alpha: 0.22 * fade)) }
                }
                let h = segPos(0, f)
                let d = CGPoint(x: CGFloat(dir.0), y: CGFloat(dir.1))
                let perp = CGPoint(x: -d.y, y: d.x)
                if Int(t * 3) % 4 == 0, state == .playing {
                    c.line(from: CGPoint(x: h.x + d.x * 2.8, y: h.y + d.y * 2.8), to: CGPoint(x: h.x + d.x * 5, y: h.y + d.y * 5), NSColor(hex: "#ff3d68"), width: 0.6)
                }
                for s: CGFloat in [-1, 1] {
                    let e = CGPoint(x: h.x + d.x * 0.9 + perp.x * 1.3 * s, y: h.y + d.y * 0.9 + perp.y * 1.3 * s)
                    c.circle(center: e, radius: 1.0, .white)
                    c.circle(center: CGPoint(x: e.x + d.x * 0.35, y: e.y + d.y * 0.35), radius: 0.55, .black)
                }
            }
        }
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.35)
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init("LENGTH", "\(snake.count)"), .init("BEST", "\(max(score, HighScores.get(id)))", color: NSColor(white: 0.75, alpha: 1))],
                   accent: NSColor(hex: "#7dff9b"), pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "SNAKE", tagline: "eat · grow · don't bite yourself", accent: NSColor(hex: "#7dff9b"), accent2: NSColor(hex: "#ffd23f"),
                             hints: [("← → ↑ ↓", "steer"), ("TAP", "¼ zones")], best: HighScores.get(id))
        case .dead:
            Arcade.overCard(c, age: t - stateT, title: "BITTEN!", score: score, best: HighScores.get(id), newBest: newBest, accent: NSColor(hex: "#ff5a5f"),
                            stats: "length \(snake.count)")
        case .playing: break
        }
    }

    private func drawFruit(_ c: Canvas, _ p: (Int, Int), gold: Bool) {
        let center = CGPoint(x: x0 + (CGFloat(p.0) + 0.5) * cell, y: (CGFloat(p.1) + 0.5) * cell)
        let bob = CGFloat(sin(t * 5 + Double(p.0))) * 0.35
        let col = gold ? NSColor(hex: "#ffd23f") : NSColor(hex: "#ff4757")
        Glow.radial(c, center, gold ? 9 : 6, col, alpha: 0.45 + 0.15 * CGFloat(sin(t * 6)))
        let r: CGFloat = gold ? 2.5 : 2.2
        c.circle(center: CGPoint(x: center.x, y: center.y + bob), radius: r, col)
        c.circle(center: CGPoint(x: center.x - 0.7, y: center.y + 0.8 + bob), radius: r * 0.35, NSColor(white: 1, alpha: 0.65))
        c.fill(CGRect(x: center.x - 0.2, y: center.y + r - 0.3 + bob, width: 0.5, height: 1.2), NSColor(hex: "#6b3e1e"))
        c.polygon([CGPoint(x: center.x + 0.2, y: center.y + r + 0.6 + bob), CGPoint(x: center.x + 1.8, y: center.y + r + 1.4 + bob),
                   CGPoint(x: center.x + 0.6, y: center.y + r + 0.1 + bob)], NSColor(hex: "#3ddc84"))
        if gold { Icons.sparkle(c, CGPoint(x: center.x + 2.5, y: center.y + 2.5), 1.6 + CGFloat(sin(t * 8)) * 0.6, .white) }
    }

    public func touchBegan(_ t: StripTouch) {
        guard state == .playing, !demo else { start(); return }
        let f = (t.x - x0) / max(1, CGFloat(cols) * cell)
        switch f {
        case ..<0.25: turn((0, 1))
        case ..<0.5: turn((-1, 0))
        case ..<0.75: turn((1, 0))
        default: turn((0, -1))
        }
    }

    public func keyDown(_ key: GameKey) {
        if demo { start(); return }
        switch key {
        case .left: turn((-1, 0))
        case .right: turn((1, 0))
        case .up: turn((0, 1))
        case .down: turn((0, -1))
        case .jump, .action, .run: if state != .playing { start() }
        default: break
        }
    }
}

// MARK: - Pong

/// Long-court Pong: you defend the bottom edge, the bot defends the top. Rallies speed up; first to 7.
public final class PongGame: StripMode, DemoStartable {
    public let id = "pong"
    public let title = "Pong"
    public let icon = "circle.lefthalf.filled"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private enum State { case title, serve, playing, over }
    private var state: State = .title
    private var stateT = 0.0
    private var t = 0.0
    private var width: CGFloat = 1004
    private var ball = CGPoint(x: 500, y: 15)
    private var vel = CGPoint(x: 160, y: 60)
    private var trail: [CGPoint] = []
    private var player: CGFloat = 500, playerV: CGFloat = 0
    private var ai: CGFloat = 500
    private let paddleW: CGFloat = 96
    private var you = 0, them = 0
    private var rally = 0
    private var holding: CGFloat?
    private var keyDir: CGFloat = 0
    private var hitStop = 0.0
    private var demo = false
    private var serveToPlayer = true
    private var squashP: CGFloat = 0, squashA: CGFloat = 0
    private var pulse: CGFloat = 0
    private let particles = Particles()
    private let shake = Shake(maxOffset: 2.2)
    private var pops: [Arcade.Popup] = []
    private let target = 7
    private var left: CGFloat { StripController.gameChromeWidth + 6 }

    public init() {}
    public func activate(_ ctx: ModeContext) {}
    public func startDemo() { demo = true; begin() }

    private func begin() { you = 0; them = 0; serve(toPlayer: true) }
    private func serve(toPlayer: Bool) {
        state = .serve; stateT = t; rally = 0; trail = []
        serveToPlayer = toPlayer
        ball = CGPoint(x: (left + width) / 2, y: 15)
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt)); Arcade.update(&pops, dt)
        pulse = max(0, pulse - CGFloat(dt) * 3)
        squashP = max(0, squashP - CGFloat(dt) * 5); squashA = max(0, squashA - CGFloat(dt) * 5)
        if hitStop > 0 { hitStop -= dt; return }
        let dt = CGFloat(dt)
        let old = player
        if demo {
            let aim = vel.y < 0 ? ball.x + vel.x * (ball.y - 4) / max(1, -vel.y) : (left + width) / 2
            player += max(-420 * dt, min(420 * dt, aim - player))
        } else if let h = holding { player += (h - player) * min(1, dt * 22) } else { player += keyDir * 520 * dt }
        player = max(left + paddleW / 2, min(width - paddleW / 2, player))
        playerV = (player - old) / max(dt, 0.001)
        let aiSpeed: CGFloat = 230 + CGFloat(rally) * 9 + CGFloat(you) * 14
        let aimAI = vel.y > 0 ? ball.x : (left + width) / 2
        ai += max(-aiSpeed * dt, min(aiSpeed * dt, aimAI - ai))
        ai = max(left + paddleW / 2, min(width - paddleW / 2, ai))
        if state == .serve {
            ball = CGPoint(x: serveToPlayer ? player : ai, y: serveToPlayer ? 7 : 23)
            if t - stateT > 0.9 {
                state = .playing
                vel = CGPoint(x: (serveToPlayer ? 1 : -1) * 150, y: serveToPlayer ? 62 : -62)
            }
            return
        }
        guard state == .playing else { return }
        ball.x += vel.x * dt; ball.y += vel.y * dt
        trail.append(ball); if trail.count > 14 { trail.removeFirst() }
        if ball.x < left + 2 { ball.x = left + 2; vel.x = abs(vel.x); wallHit() }
        if ball.x > width - 2 { ball.x = width - 2; vel.x = -abs(vel.x); wallHit() }
        if ball.y < 5.5, vel.y < 0 {
            if abs(ball.x - player) < paddleW / 2 + 3 {
                ball.y = 5.5; vel.y = abs(vel.y) * 1.035
                vel.x = vel.x * 0.6 + (ball.x - player) * 4.2 + playerV * 0.25
                hit(at: CGPoint(x: ball.x, y: 4), color: NSColor(hex: "#3df5ff")); squashP = 1
            } else if ball.y < -3 { point(forPlayer: false) }
        }
        if ball.y > 24.5, vel.y > 0 {
            if abs(ball.x - ai) < paddleW / 2 + 3 {
                ball.y = 24.5; vel.y = -abs(vel.y) * 1.035
                vel.x = vel.x * 0.6 + (ball.x - ai) * 3.2
                hit(at: CGPoint(x: ball.x, y: 26), color: NSColor(hex: "#ff4fd8")); squashA = 1
            } else if ball.y > 33 { point(forPlayer: true) }
        }
        vel.y = max(-140, min(140, vel.y)); vel.x = max(-560, min(560, vel.x))
    }

    private func wallHit() {
        particles.burst(x: ball.x, y: ball.y, count: 5, colors: [.white], speed: 40, life: 0.25, size: 1, gravity: 0, kind: .streak, drag: 4)
    }

    private func hit(at p: CGPoint, color: NSColor) {
        rally += 1; hitStop = 0.035
        shake.add(0.12 + min(0.25, CGFloat(rally) * 0.02))
        particles.burst(x: p.x, y: p.y, count: 12, colors: [color, .white], speed: 70, life: 0.35, size: 1.2, gravity: 0, kind: .streak, drag: 4,
                        direction: p.y < 15 ? .pi / 2 : -.pi / 2, spread: 2.2)
        particles.ring(x: p.x, y: p.y, color: color, radius: 8, life: 0.25)
        if rally > 0, rally % 5 == 0 { pops.append(.init(x: p.x, y: 15, text: "RALLY \(rally)", color: NSColor(hex: "#ffd23f"))) }
    }

    private func point(forPlayer: Bool) {
        if forPlayer { you += 1; pulse = 1 } else { them += 1 }
        shake.add(0.5)
        let x = ball.x, y: CGFloat = forPlayer ? 28 : 2
        let col = forPlayer ? NSColor(hex: "#3df5ff") : NSColor(hex: "#ff4fd8")
        particles.burst(x: x, y: y, count: 30, colors: [col, .white, NSColor(hex: "#ffd23f")], speed: 110, life: 0.7, size: 1.6, gravity: 0, kind: .sparkle, drag: 3)
        particles.flash(x: x, y: y, color: col, radius: 26, life: 0.2)
        pops.append(.init(x: x, y: 12, text: forPlayer ? "POINT!" : "MISS", color: col, life: 1))
        if you >= target || them >= target {
            state = .over; stateT = t
            if you >= target { _ = HighScores.submit(id, you - them) }
        } else { serve(toPlayer: !forPlayer) }
    }

    public func draw(_ c: Canvas) {
        width = c.width - 4
        c.gradient(c.bounds, [NSColor(hex: "#120a2e"), NSColor(hex: "#05030f")])
        // perspective grid floor
        for i in 0..<40 {
            let gx = left + CGFloat(i) * (width - left) / 39
            c.line(from: CGPoint(x: gx, y: 0), to: CGPoint(x: (left + width) / 2 + (gx - (left + width) / 2) * 0.92, y: 30), NSColor(hex: "#6c3cff", alpha: 0.10), width: 0.5)
        }
        for y in stride(from: CGFloat(3), to: 30, by: 6) { c.fill(CGRect(x: left, y: y, width: width - left, height: 0.4), NSColor(hex: "#6c3cff", alpha: 0.08)) }
        let mid = (left + width) / 2
        var y: CGFloat = 1
        while y < 30 { c.fill(CGRect(x: mid - 0.6, y: y, width: 1.2, height: 2), NSColor(white: 1, alpha: 0.18)); y += 4 }
        c.fill(CGRect(x: left, y: 14.8, width: width - left, height: 0.4), NSColor(white: 1, alpha: 0.06))
        // big ghost scores
        Arcade.display(c, "\(them)", x: mid + 40, y: 8, size: 16, color: NSColor(hex: "#ff4fd8", alpha: 0.22), shadow: .clear)
        Arcade.display(c, "\(you)", x: mid - 40, y: 8, size: 16, color: NSColor(hex: "#3df5ff", alpha: 0.22), align: .right, shadow: .clear)
        c.cg.saveGState()
        shake.apply(c)
        paddle(c, x: player, y: 2, color: NSColor(hex: "#3df5ff"), squash: squashP, top: false)
        paddle(c, x: ai, y: 25.5, color: NSColor(hex: "#ff4fd8"), squash: squashA, top: true)
        if state == .serve || state == .playing {
            for (i, p) in trail.enumerated() {
                let k = CGFloat(i) / CGFloat(max(1, trail.count))
                c.circle(center: p, radius: 0.6 + 1.4 * k, NSColor(hex: "#ffe066", alpha: 0.35 * k))
            }
            let speed = hypot(vel.x, vel.y)
            Glow.radial(c, ball, 7 + speed / 120, NSColor(hex: "#ffe066"), alpha: 0.5)
            c.circle(center: ball, radius: 2.3, .white)
            c.circle(center: CGPoint(x: ball.x - 0.6, y: ball.y + 0.6), radius: 0.9, NSColor(hex: "#fff8d0"))
            if state == .serve {
                let k = CGFloat((t - stateT) / 0.9)
                c.circle(center: ball, radius: 4 + 8 * (1 - k), NSColor.clear)
                c.cg.setStrokeColor(NSColor(white: 1, alpha: 0.6 * k).cgColor); c.cg.setLineWidth(0.6)
                c.cg.strokeEllipse(in: CGRect(x: ball.x - (4 + 8 * (1 - k)), y: ball.y - (4 + 8 * (1 - k)), width: 2 * (4 + 8 * (1 - k)), height: 2 * (4 + 8 * (1 - k))))
            }
        }
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.3)
        Arcade.hud(c, [.init("YOU", "\(you)", color: NSColor(hex: "#3df5ff")), .init("BOT", "\(them)", color: NSColor(hex: "#ff4fd8")), .init("RALLY", "\(rally)")],
                   accent: NSColor(hex: "#b48cff"), pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "PONG", tagline: "first to \(target) · rallies speed up", accent: NSColor(hex: "#3df5ff"), accent2: NSColor(hex: "#ff4fd8"),
                             hints: [("← →", "move"), ("DRAG", "slide paddle")], best: nil)
        case .over:
            let won = you >= target
            Arcade.overCard(c, age: t - stateT, title: won ? "YOU WIN!" : "BOT WINS", score: you, best: you, newBest: false,
                            accent: won ? NSColor(hex: "#3df5ff") : NSColor(hex: "#ff4fd8"), stats: "\(you) – \(them)")
        default: break
        }
    }

    private func paddle(_ c: Canvas, x: CGFloat, y: CGFloat, color: NSColor, squash: CGFloat, top: Bool) {
        let w = paddleW * (1 + 0.08 * squash), h = 2.6 * (1 - 0.3 * squash)
        let r = CGRect(x: x - w / 2, y: y + (top ? 2.6 - h : 0), width: w, height: h)
        Glow.capsule(c, r, color, halo: 3 + 2 * squash, intensity: 0.35 + 0.4 * squash)
        c.gradient(r, [color.blended(withFraction: 0.5, of: .white) ?? color, color], radius: h / 2)
        c.fill(CGRect(x: r.minX + 4, y: r.midY + 0.2, width: r.width - 8, height: 0.5), NSColor(white: 1, alpha: 0.6))
    }

    private func press() {
        if demo { demo = false; begin(); return }
        switch state {
        case .title: begin()
        case .over where t - stateT > 0.8: begin()
        default: break
        }
    }

    public func touchBegan(_ t: StripTouch) { if state == .title || state == .over || demo { press() } else { holding = t.x } }
    public func touchMoved(_ t: StripTouch) { if holding != nil { holding = t.x } }
    public func touchEnded(_ t: StripTouch) { holding = nil }

    public func keyDown(_ key: GameKey) {
        switch key {
        case .left: keyDir = -1; if demo { press() }
        case .right: keyDir = 1; if demo { press() }
        case .jump, .action, .run: press()
        default: break
        }
    }
    public func keyUp(_ key: GameKey) {
        if (key == .left && keyDir < 0) || (key == .right && keyDir > 0) { keyDir = 0 }
    }
}

// MARK: - Breakout

/// Breakout along the strip: bricks overhead, paddle at the bottom, power-up capsules, multi-ball and levels.
public final class BreakoutGame: StripMode, DemoStartable {
    public let id = "breakout"
    public let title = "Breakout"
    public let icon = "square.grid.3x1.below.line.grid.1x2"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Brick { var r: CGRect; var hp: Int; var row: Int; var hitT: Double = -9 }
    private struct Ball { var p: CGPoint; var v: CGPoint; var trail: [CGPoint] = [] }
    private struct Drop { var p: CGPoint; var kind: Int }
    private enum State { case title, ready, playing, cleared, over }
    private var state: State = .title
    private var stateT = 0.0
    private var t = 0.0
    private var width: CGFloat = 1004
    private var bricks: [Brick] = []
    private var balls: [Ball] = []
    private var drops: [Drop] = []
    private var paddle: CGFloat = 500
    private var wideUntil = 0.0
    private var lives = 3, score = 0, level = 1, combo = 0
    private var newBest = false
    private var holding: CGFloat?
    private var keyDir: CGFloat = 0
    private var hitStop = 0.0
    private var demo = false
    private var pulse: CGFloat = 0, squash: CGFloat = 0
    private let particles = Particles()
    private let shake = Shake(maxOffset: 2.4)
    private var pops: [Arcade.Popup] = []
    private var rng = SeededRNG(seed: 7)
    private var left: CGFloat { StripController.gameChromeWidth + 6 }
    private var paddleW: CGFloat { t < wideUntil ? 120 : 76 }
    private static let rowColors = ["#ff4d6d", "#ff9f1c", "#ffd23f", "#3ddc84", "#3df5ff"].map { NSColor(hex: $0) }

    public init() {}
    public func activate(_ ctx: ModeContext) {}
    public func startDemo() { demo = true; newGame(); launch() }

    private func newGame() { lives = 3; score = 0; level = 1; newBest = false; build(); ready() }
    private func ready() { state = .ready; stateT = t; balls = [Ball(p: CGPoint(x: paddle, y: 6.5), v: .zero)]; drops = []; combo = 0 }
    private func launch() {
        state = .playing; stateT = t
        let s: CGFloat = 175 + CGFloat(level - 1) * 18
        balls = balls.map { var b = $0; b.v = CGPoint(x: s * 0.8, y: s * 0.32); return b }
    }

    private func build() {
        bricks = []
        let bw: CGFloat = 34, bh: CGFloat = 3.2, gap: CGFloat = 1.6
        let span = width - 210 - left
        let n = Int(span / (bw + gap))
        let x0 = left + 10 + (span - CGFloat(n) * (bw + gap)) / 2
        let pattern = level % 3
        for row in 0..<3 { for i in 0..<n {
            let keep: Bool
            switch pattern {
            case 1: keep = (i + row) % 5 != 0
            case 2: keep = abs(i - n / 2) % 7 != row
            default: keep = true
            }
            guard keep else { continue }
            let hp = row == 2 && level > 1 && i % 3 == 0 ? 2 : 1
            bricks.append(Brick(r: CGRect(x: x0 + CGFloat(i) * (bw + gap), y: 15.5 + CGFloat(row) * (bh + gap), width: bw, height: bh), hp: hp, row: row))
        } }
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt)); Arcade.update(&pops, dt)
        pulse = max(0, pulse - CGFloat(dt) * 3); squash = max(0, squash - CGFloat(dt) * 5)
        if hitStop > 0 { hitStop -= dt; return }
        let dt = CGFloat(dt)
        if demo, let b = balls.min(by: { $0.p.y < $1.p.y }) {
            let aim = b.p.x + sin(CGFloat(t) * 0.7) * 20
            paddle += max(-460 * dt, min(460 * dt, aim - paddle))
        } else if let h = holding { paddle += (h - paddle) * min(1, dt * 22) } else { paddle += keyDir * 480 * dt }
        paddle = max(left + paddleW / 2, min(width - paddleW / 2, paddle))
        switch state {
        case .ready:
            balls = [Ball(p: CGPoint(x: paddle, y: 6.5), v: .zero)]
            if demo, t - stateT > 0.6 { launch() }
            return
        case .cleared:
            if t - stateT > 1.6 { level += 1; build(); ready() }
            return
        case .playing: break
        default: return
        }
        for i in drops.indices { drops[i].p.y -= 22 * dt }
        drops.removeAll { d in
            if d.p.y < 5, abs(d.p.x - paddle) < paddleW / 2 + 5 { collect(d); return true }
            return d.p.y < -4
        }
        var lost: [Int] = []
        for bi in balls.indices {
            var b = balls[bi]
            b.p.x += b.v.x * dt; b.p.y += b.v.y * dt
            b.trail.append(b.p); if b.trail.count > 10 { b.trail.removeFirst() }
            if b.p.x < left + 1.5 { b.p.x = left + 1.5; b.v.x = abs(b.v.x) }
            if b.p.x > width - 1.5 { b.p.x = width - 1.5; b.v.x = -abs(b.v.x) }
            if b.p.y > 28.5 { b.p.y = 28.5; b.v.y = -abs(b.v.y) }
            if b.p.y < 5, b.v.y < 0, abs(b.p.x - paddle) < paddleW / 2 + 2 {
                b.p.y = 5; b.v.y = abs(b.v.y)
                let speed = hypot(b.v.x, b.v.y)
                let off = (b.p.x - paddle) / (paddleW / 2)
                let ang = CGFloat.pi / 2 - off * 1.25
                b.v = CGPoint(x: cos(ang) * speed, y: max(40, sin(ang) * speed * 0.42))
                squash = 1; combo = 0
                particles.burst(x: b.p.x, y: 4, count: 6, colors: [NSColor(hex: "#3df5ff"), .white], speed: 40, life: 0.25, size: 1, gravity: 0, kind: .streak, drag: 5, direction: .pi / 2, spread: 2)
            }
            if b.p.y < -3 { lost.append(bi) }
            if let k = bricks.firstIndex(where: { $0.r.insetBy(dx: -1.8, dy: -1.8).contains(b.p) }) {
                let r = bricks[k].r
                let fromSide = b.p.y > r.minY + 0.5 && b.p.y < r.maxY - 0.5
                if fromSide { b.v.x = -b.v.x } else { b.v.y = -b.v.y }
                b.p.x += b.v.x * dt * 2; b.p.y += b.v.y * dt * 2
                hitBrick(k)
            }
            balls[bi] = b
        }
        for i in lost.reversed() { balls.remove(at: i) }
        if balls.isEmpty { loseLife() }
        if bricks.isEmpty, state == .playing {
            state = .cleared; stateT = t; score += 250 * level; pulse = 1
            pops.append(.init(x: (left + width) / 2, y: 10, text: "LEVEL CLEAR +\(250 * level)", color: NSColor(hex: "#ffd23f"), life: 1.5))
            particles.flash(x: (left + width) / 2, y: 15, color: NSColor(hex: "#ffd23f"), radius: 60, life: 0.3)
        }
    }

    private func hitBrick(_ k: Int) {
        bricks[k].hp -= 1; bricks[k].hitT = t
        let r = bricks[k].r
        let col = Self.rowColors[(bricks[k].row + level - 1) % 5]
        if bricks[k].hp > 0 { shake.add(0.06); return }
        combo += 1
        let pts = 10 * (bricks[k].row + 1) * min(combo, 8)
        score += pts; pulse = 1
        hitStop = combo > 3 ? 0.03 : 0.015
        shake.add(0.1 + min(0.2, CGFloat(combo) * 0.03))
        particles.burst(x: r.midX, y: r.midY, count: 12, colors: [col, col.blended(withFraction: 0.5, of: .white) ?? col], speed: 60, life: 0.55, size: 1.6, gravity: -140, kind: .shard, upBias: 0.2)
        particles.flash(x: r.midX, y: r.midY, color: col, radius: 12)
        if combo >= 3 { pops.append(.init(x: r.midX, y: r.minY - 4, text: "×\(min(combo, 8)) +\(pts)", color: col)) }
        bricks.remove(at: k)
        if rng.next(9) == 0 { drops.append(Drop(p: CGPoint(x: r.midX, y: r.minY), kind: rng.next(3))) }
    }

    private func collect(_ d: Drop) {
        pulse = 1
        particles.ring(x: d.p.x, y: 4, color: .white, radius: 14)
        switch d.kind {
        case 0: wideUntil = t + 12; pops.append(.init(x: d.p.x, y: 10, text: "WIDE", color: NSColor(hex: "#3df5ff")))
        case 1:
            if let b = balls.first {
                balls.append(Ball(p: b.p, v: CGPoint(x: -b.v.x, y: abs(b.v.y))))
                balls.append(Ball(p: b.p, v: CGPoint(x: b.v.x * 0.7, y: abs(b.v.y) * 1.2)))
            }
            pops.append(.init(x: d.p.x, y: 10, text: "MULTI", color: NSColor(hex: "#ff4fd8")))
        default: lives += 1; pops.append(.init(x: d.p.x, y: 10, text: "1UP", color: NSColor(hex: "#3ddc84")))
        }
    }

    private func loseLife() {
        lives -= 1; shake.add(0.6)
        particles.flash(x: paddle, y: 2, color: NSColor(hex: "#ff4d6d"), radius: 40, life: 0.25)
        if lives <= 0 { state = .over; stateT = t; newBest = HighScores.submit(id, score) } else { ready() }
    }

    public func draw(_ c: Canvas) {
        width = c.width - 4
        c.gradient(c.bounds, [NSColor(hex: "#0d1a3a"), NSColor(hex: "#050814")])
        for i in 0..<60 { // starfield, slow drift
            let x = (CGFloat(i) * 97.3 + CGFloat(t) * (3 + CGFloat(i % 3) * 3)).truncatingRemainder(dividingBy: c.width)
            c.fill(CGRect(x: x, y: CGFloat((i * 37) % 29), width: 0.8, height: 0.8), NSColor(white: 1, alpha: 0.15 + CGFloat(i % 4) * 0.08))
        }
        c.cg.saveGState()
        shake.apply(c)
        for b in bricks {
            let col = Self.rowColors[(b.row + level - 1) % 5]
            let flash = t - b.hitT < 0.08
            let wob = CGFloat(sin((t + Double(b.r.minX) * 0.01) * 2)) * 0.25
            let r = b.r.offsetBy(dx: 0, dy: wob)
            c.roundRect(r.offsetBy(dx: 0.5, dy: -0.6), radius: 1, fill: NSColor(white: 0, alpha: 0.35))
            c.gradient(r, [flash ? .white : (col.blended(withFraction: 0.25, of: .white) ?? col), flash ? .white : (col.blended(withFraction: 0.3, of: .black) ?? col)], radius: 1)
            c.fill(CGRect(x: r.minX + 1, y: r.maxY - 0.8, width: r.width - 2, height: 0.5), NSColor(white: 1, alpha: 0.45))
            if b.hp > 1 { c.roundRect(r.insetBy(dx: 0.4, dy: 0.4), radius: 1, fill: .clear, stroke: NSColor(white: 1, alpha: 0.8), lineWidth: 0.5) }
        }
        for d in drops {
            let col = [NSColor(hex: "#3df5ff"), NSColor(hex: "#ff4fd8"), NSColor(hex: "#3ddc84")][d.kind]
            let r = CGRect(x: d.p.x - 6, y: d.p.y - 2, width: 12, height: 4)
            Glow.capsule(c, r, col)
            c.gradient(r, [col.blended(withFraction: 0.4, of: .white) ?? col, col], radius: 2)
            c.text(["W", "M", "+"][d.kind], x: r.midX, y: r.minY - 0.6, size: 4.5, color: Arcade.ink, weight: .black, align: .center)
        }
        let w = paddleW * (1 + 0.06 * squash)
        let pr = CGRect(x: paddle - w / 2, y: 2, width: w, height: 2.6 * (1 - 0.25 * squash))
        Glow.capsule(c, pr, NSColor(hex: "#3df5ff"), intensity: 0.3 + 0.3 * squash)
        c.gradient(pr, [NSColor(hex: "#bff9ff"), NSColor(hex: "#2aa8c9")], radius: 1.3)
        c.fill(CGRect(x: pr.minX + 3, y: pr.minY, width: 3, height: pr.height), NSColor(hex: "#ff4d6d"))
        c.fill(CGRect(x: pr.maxX - 6, y: pr.minY, width: 3, height: pr.height), NSColor(hex: "#ff4d6d"))
        for b in balls {
            for (i, p) in b.trail.enumerated() {
                let k = CGFloat(i) / CGFloat(max(1, b.trail.count))
                c.circle(center: p, radius: 0.5 + 1.1 * k, NSColor(hex: "#fff3b0", alpha: 0.3 * k))
            }
            Glow.radial(c, b.p, 6, NSColor(hex: "#fff3b0"), alpha: 0.5)
            c.circle(center: b.p, radius: 1.8, .white)
        }
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        Glow.vignette(c, strength: 0.3)
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init(lives: lives), .init("LVL", "\(level)")], accent: NSColor(hex: "#ffd23f"), pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "BREAKOUT", tagline: "chain hits for combo multipliers", accent: NSColor(hex: "#ffd23f"), accent2: NSColor(hex: "#ff4d6d"),
                             hints: [("← →", "move"), ("SPACE", "launch"), ("DRAG", "slide")], best: HighScores.get(id))
        case .ready where !demo:
            let a = CGFloat(0.55 + 0.45 * sin(t * 5))
            c.text("SPACE / TAP TO LAUNCH", x: paddle, y: 8.5, size: 6, color: NSColor(white: 1, alpha: a), weight: .heavy, align: .center)
        case .over:
            Arcade.overCard(c, age: t - stateT, title: "GAME OVER", score: score, best: HighScores.get(id), newBest: newBest, accent: NSColor(hex: "#ff4d6d"), stats: "level \(level)")
        default: break
        }
    }

    private func press() {
        if demo { demo = false; newGame(); return }
        switch state {
        case .title: newGame()
        case .ready: launch()
        case .over where t - stateT > 0.8: newGame()
        default: break
        }
    }

    public func touchBegan(_ t: StripTouch) {
        if state == .title || state == .over || state == .ready || demo { press() }
        holding = t.x
    }
    public func touchMoved(_ t: StripTouch) { if holding != nil { holding = t.x } }
    public func touchEnded(_ t: StripTouch) { holding = nil }
    public func keyDown(_ key: GameKey) {
        switch key {
        case .left: keyDir = -1
        case .right: keyDir = 1
        case .jump, .action, .run, .up: press()
        default: break
        }
    }
    public func keyUp(_ key: GameKey) {
        if (key == .left && keyDir < 0) || (key == .right && keyDir > 0) { keyDir = 0 }
    }
}

// MARK: - Flap

/// Flap: a little bird threading pipes across a parallax dusk sky.
public final class FlappyGame: StripMode, DemoStartable {
    public let id = "flappy"
    public let title = "Flap"
    public let icon = "bird"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Pipe { var x: CGFloat; var gapY: CGFloat; var gap: CGFloat; var scored = false; var coin = true }
    private enum State { case title, playing, dead }
    private var state: State = .title
    private var stateT = 0.0
    private var t = 0.0
    private var width: CGFloat = 1004
    private var y: CGFloat = 15, vy: CGFloat = 0
    private var pipes: [Pipe] = []
    private var dist: CGFloat = 0
    private var score = 0
    private var newBest = false
    private var flapT = -9.0
    private var demo = false
    private var pulse: CGFloat = 0
    private let particles = Particles()
    private let shake = Shake(maxOffset: 3)
    private var pops: [Arcade.Popup] = []
    private var rng = SeededRNG(seed: 11)
    private var birdX: CGFloat { StripController.gameChromeWidth + 90 }
    private var speed: CGFloat { min(150, 92 + CGFloat(score) * 2.2) }

    public init() {}
    public func activate(_ ctx: ModeContext) {}
    public func startDemo() { demo = true; start() }

    private func start() {
        state = .playing; stateT = t; y = 15; vy = 60; score = 0; newBest = false; pipes = []
        var x = birdX + 160
        while x < width + 200 { spawn(at: x); x += spacing() }
        flapT = t
    }
    private func spacing() -> CGFloat { max(92, 140 - CGFloat(score) * 1.6) }
    private func spawn(at x: CGFloat) {
        let gap = max(13, 17 - CGFloat(score) * 0.08)
        pipes.append(Pipe(x: x, gapY: gap / 2 + 2 + CGFloat(rng.next(Int(26 - gap))), gap: gap))
    }

    private func flap() {
        vy = 64; flapT = t
        particles.burst(x: birdX - 3, y: y - 1, count: 3, colors: [NSColor(white: 1, alpha: 0.8)], speed: 25, life: 0.3, size: 1.2, gravity: 0, kind: .dot, drag: 4, direction: .pi, spread: 1)
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt)); Arcade.update(&pops, dt)
        pulse = max(0, pulse - CGFloat(dt) * 3)
        let dt = CGFloat(dt)
        if state == .title { y = 15 + sin(CGFloat(t) * 3) * 2; dist += 40 * dt; return }
        if state == .dead {
            if y > 1.5 { vy -= 360 * dt; y = max(1.5, y + vy * dt) }
            return
        }
        dist += speed * dt
        vy = max(-95, vy - 270 * dt)
        y += vy * dt
        if demo, let p = pipes.first(where: { $0.x + 10 > birdX - 4 }) {
            if y < p.gapY - 2.5, vy < 5 { flap() }
        }
        for i in pipes.indices {
            pipes[i].x -= speed * dt
            if !pipes[i].scored, pipes[i].x + 6 < birdX {
                pipes[i].scored = true; score += 1; pulse = 1
                if pipes[i].coin {
                    particles.burst(x: birdX, y: pipes[i].gapY, count: 10, colors: [NSColor(hex: "#ffd23f"), .white], speed: 50, life: 0.4, size: 1.6, gravity: 0, kind: .sparkle, drag: 4)
                    pops.append(.init(x: birdX + 10, y: pipes[i].gapY + 3, text: "+1", color: NSColor(hex: "#ffd23f")))
                }
                if score % 10 == 0 { pops.append(.init(x: birdX + 40, y: 14, text: "\(score)!", color: .white, life: 1.2)); shake.add(0.2) }
            }
        }
        pipes.removeAll { $0.x < -20 }
        if let last = pipes.last, last.x < width + 40 { spawn(at: last.x + spacing()) }
        if y > 29 { y = 29; vy = min(vy, 0) }
        let hit = y < 1.5 || pipes.contains { p in
            abs(p.x - birdX) < 9.5 && (y - 3 < p.gapY - p.gap / 2 || y + 3 > p.gapY + p.gap / 2)
        }
        if hit { die() }
    }

    private func die() {
        state = .dead; stateT = t; vy = 70
        newBest = HighScores.submit(id, score)
        shake.add(0.8)
        particles.flash(x: birdX, y: y, color: .white, radius: 20, life: 0.15)
        particles.burst(x: birdX, y: y, count: 18, colors: [NSColor(hex: "#ffd23f"), NSColor(hex: "#ff9f1c"), .white], speed: 70, life: 0.8, size: 1.5, gravity: -150, kind: .square)
    }

    public func draw(_ c: Canvas) {
        width = c.width
        c.gradient(c.bounds, [NSColor(hex: "#ff9a62"), NSColor(hex: "#ffd39b"), NSColor(hex: "#8ec5ff")].reversed())
        Glow.radial(c, CGPoint(x: c.width * 0.72, y: 10), 40, NSColor(hex: "#fff1c1"), alpha: 0.7)
        c.circle(center: CGPoint(x: c.width * 0.72, y: 10), radius: 9, NSColor(hex: "#fff6dc"))
        for i in 0..<9 { // clouds, far
            let x = (CGFloat(i) * 151 - dist * 0.08).truncatingRemainder(dividingBy: c.width + 60)
            let cx = x < -30 ? x + c.width + 60 : x
            let cy: CGFloat = 20 + CGFloat(i % 3) * 3
            for (dx, r) in [(0, 3.5), (4, 4.5), (9, 3.2)] as [(CGFloat, CGFloat)] { c.circle(center: CGPoint(x: cx + dx, y: cy), radius: r, NSColor(white: 1, alpha: 0.55)) }
        }
        drawSkyline(c, factor: 0.2, base: 4, color: NSColor(hex: "#b48ac9", alpha: 0.55), seed: 3, maxH: 12)
        drawSkyline(c, factor: 0.4, base: 2, color: NSColor(hex: "#7d5aa6", alpha: 0.75), seed: 9, maxH: 8)
        c.cg.saveGState()
        shake.apply(c)
        for p in pipes { drawPipe(c, p) }
        // ground
        c.gradient(CGRect(x: 0, y: 0, width: c.width, height: 2), [NSColor(hex: "#7ed957"), NSColor(hex: "#3c9a3c")])
        var gx = -(dist.truncatingRemainder(dividingBy: 6))
        while gx < c.width { c.fill(CGRect(x: gx, y: 1.2, width: 3, height: 0.8), NSColor(hex: "#a8ec7a")); gx += 6 }
        drawBird(c)
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        if state == .playing {
            Arcade.display(c, "\(score)", x: birdX + 40, y: 9, size: 13 + 4 * pulse, color: .white, align: .center)
        }
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init("BEST", "\(max(score, HighScores.get(id)))", color: NSColor(white: 0.8, alpha: 1))], accent: NSColor(hex: "#ffd23f"), pulse: pulse)
        switch state {
        case .title:
            Arcade.titleCard(c, age: t - stateT, title: "FLAP", tagline: "thread the pipes · it speeds up", accent: NSColor(hex: "#ffd23f"), accent2: NSColor(hex: "#ff7b54"),
                             hints: [("SPACE ↑", "flap"), ("TAP", "flap")], best: HighScores.get(id))
        case .dead:
            let medal = score >= 40 ? "PLATINUM" : score >= 25 ? "GOLD" : score >= 10 ? "SILVER" : score >= 5 ? "BRONZE" : "no medal"
            Arcade.overCard(c, age: t - stateT, title: "OUCH!", score: score, best: HighScores.get(id), newBest: newBest, accent: NSColor(hex: "#ff7b54"), stats: medal)
        case .playing: break
        }
    }

    private func drawSkyline(_ c: Canvas, factor: CGFloat, base: CGFloat, color: NSColor, seed: Int, maxH: CGFloat) {
        let w: CGFloat = 22
        let off = (dist * factor).truncatingRemainder(dividingBy: w)
        let start = Int(dist * factor / w)
        var x = -off
        var i = start
        while x < c.width {
            let h = base + CGFloat(((i &* 2654435761 &+ seed) >> 3) % Int(maxH))
            c.fill(CGRect(x: x, y: 0, width: w - 3, height: h), color)
            if h > base + 4 { c.fill(CGRect(x: x + 3, y: h - 3, width: 1.4, height: 1.4), NSColor(hex: "#ffe7a3", alpha: 0.5)) }
            x += w; i += 1
        }
    }

    private func drawPipe(_ c: Canvas, _ p: Pipe) {
        let w: CGFloat = 12
        let low = p.gapY - p.gap / 2, high = p.gapY + p.gap / 2
        for (y0, y1, capY) in [(CGFloat(0), low, low - 2.5), (high, CGFloat(30), high)] {
            let r = CGRect(x: p.x - w / 2 + 1, y: y0, width: w - 2, height: y1 - y0)
            c.gradient(r, [NSColor(hex: "#2e8b3a"), NSColor(hex: "#8fe36b"), NSColor(hex: "#3fae46"), NSColor(hex: "#1f6b2a")], horizontal: true)
            let cap = CGRect(x: p.x - w / 2, y: capY, width: w, height: 2.5)
            c.gradient(cap, [NSColor(hex: "#2e8b3a"), NSColor(hex: "#b6f58d"), NSColor(hex: "#3fae46"), NSColor(hex: "#1f6b2a")], horizontal: true)
            c.roundRect(cap, radius: 0.5, fill: .clear, stroke: NSColor(hex: "#14451b"), lineWidth: 0.5)
        }
    }

    private func drawBird(_ c: Canvas) {
        let tilt = state == .title ? 0 : max(-1.2, min(0.5, vy / 120))
        c.cg.saveGState()
        c.cg.translateBy(x: birdX, y: y)
        c.cg.rotate(by: tilt)
        c.cg.scaleBy(x: 1.35, y: 1.35)
        let dead = state == .dead
        c.circle(center: CGPoint(x: 0, y: -0.3), radius: 3.2, NSColor(hex: "#e08a00"))
        c.circle(center: .zero, radius: 3.0, NSColor(hex: "#ffcc33"))
        c.circle(center: CGPoint(x: -0.3, y: -1.2), radius: 1.9, NSColor(hex: "#fff0b3"))
        let wingPhase = dead ? 0 : (t - flapT < 0.25 ? sin((t - flapT) * 30) : sin(t * 10) * 0.4)
        let wy = CGFloat(wingPhase) * 1.6
        c.polygon([CGPoint(x: -3.2, y: 0.4), CGPoint(x: -0.4, y: 0.6), CGPoint(x: -1.8, y: 0.2 + wy - 1.4)], NSColor(hex: "#f4a300"))
        c.circle(center: CGPoint(x: 1.3, y: 1.1), radius: 1.15, .white)
        if dead {
            c.line(from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 1.9, y: 1.7), .black, width: 0.4)
            c.line(from: CGPoint(x: 0.7, y: 1.7), to: CGPoint(x: 1.9, y: 0.5), .black, width: 0.4)
        } else { c.circle(center: CGPoint(x: 1.6, y: 1.1), radius: 0.55, .black) }
        c.polygon([CGPoint(x: 2.2, y: 0.2), CGPoint(x: 4.6, y: -0.4), CGPoint(x: 2.2, y: -1.2)], NSColor(hex: "#ff6b3d"))
        c.cg.restoreGState()
    }

    private func press() {
        if demo { demo = false; start(); return }
        switch state {
        case .title: start()
        case .playing: flap()
        case .dead where t - stateT > 0.7: start()
        default: break
        }
    }
    public func touchBegan(_ t: StripTouch) { press() }
    public func keyDown(_ key: GameKey) {
        switch key {
        case .jump, .up, .action, .run: press()
        default: break
        }
    }
}

// MARK: - Starstrip

/// Starstrip: side-scrolling shooter with waves, power levels, bombs-free arcade feel and boss-lite elites.
public final class ShooterGame: StripMode, DemoStartable {
    public let id = "shooter"
    public let title = "Starstrip"
    public let icon = "airplane"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private struct Shot { var p: CGPoint; var v: CGPoint; var enemy: Bool }
    private struct Foe { var p: CGPoint; var baseY: CGFloat; var kind: Int; var hp: Int; var phase: Double; var hitT: Double = -9; var fireT: Double }
    private struct Drop { var p: CGPoint }
    private enum State { case title, playing, dead }
    private var state: State = .title
    private var stateT = 0.0
    private var t = 0.0
    private var width: CGFloat = 1004
    private var ship = CGPoint(x: 90, y: 15)
    private var vy: CGFloat = 0, vx: CGFloat = 0
    private var shots: [Shot] = []
    private var foes: [Foe] = []
    private var drops: [Drop] = []
    private var lives = 3, score = 0, power = 1, wave = 0
    private var newBest = false
    private var fireCD = 0.0, spawnT = 0.0, invuln = 0.0
    private var held: Set<GameKey> = []
    private var touchY: CGFloat?
    private var firing = false
    private var demo = false
    private var pulse: CGFloat = 0
    private var hitStop = 0.0
    private var scroll: CGFloat = 0
    private let particles = Particles()
    private let shake = Shake(maxOffset: 2.8)
    private var pops: [Arcade.Popup] = []
    private var rng = SeededRNG(seed: 5)
    private var minX: CGFloat { StripController.gameChromeWidth + 10 }

    public init() {}
    public func activate(_ ctx: ModeContext) {}
    public func startDemo() { demo = true; start() }

    private func start() {
        state = .playing; stateT = t; lives = 3; score = 0; power = 1; wave = 0; newBest = false
        shots = []; foes = []; drops = []; ship = CGPoint(x: minX + 40, y: 15); invuln = 1.5; spawnT = 0.3
    }

    public func update(dt: Double) {
        t += dt
        particles.update(CGFloat(dt)); shake.update(CGFloat(dt)); Arcade.update(&pops, dt)
        pulse = max(0, pulse - CGFloat(dt) * 3)
        let fdt = CGFloat(dt)
        scroll += fdt * (state == .playing ? 60 : 25)
        if hitStop > 0 { hitStop -= dt; return }
        guard state == .playing else { return }
        invuln -= dt
        var ty: CGFloat = 0, tx: CGFloat = 0
        if demo {
            let target = foes.filter { $0.p.x > ship.x }.min { $0.p.x < $1.p.x }
            let danger = shots.first { $0.enemy && $0.p.x > ship.x && $0.p.x - ship.x < 60 && abs($0.p.y - ship.y) < 4 }
            let aimY = danger != nil ? (ship.y > 15 ? 6 : 24) : (target?.p.y ?? 15)
            ty = max(-1, min(1, (aimY - ship.y) / 3))
            firing = true
        } else {
            if held.contains(.up) { ty += 1 }; if held.contains(.down) { ty -= 1 }
            if held.contains(.right) { tx += 1 }; if held.contains(.left) { tx -= 1 }
            if let ty0 = touchY { ty = max(-1, min(1, (ty0 - ship.y) / 3)) }
        }
        vy += (ty * 95 - vy) * min(1, fdt * 14)
        vx += (tx * 110 - vx) * min(1, fdt * 14)
        ship.y = max(3, min(27, ship.y + vy * fdt))
        ship.x = max(minX + 8, min(minX + 260, ship.x + vx * fdt))
        if firing || held.contains(.run) || held.contains(.jump) || held.contains(.action) {
            fireCD -= dt
            if fireCD <= 0 {
                fireCD = 0.14
                let spreads: [CGFloat] = power >= 3 ? [-0.16, 0, 0.16] : power == 2 ? [-0.06, 0.06] : [0]
                for s in spreads { shots.append(Shot(p: CGPoint(x: ship.x + 8, y: ship.y + s * 10), v: CGPoint(x: 420 * cos(s), y: 420 * sin(s)), enemy: false)) }
                particles.flash(x: ship.x + 9, y: ship.y, color: NSColor(hex: "#9ff3ff"), radius: 4, life: 0.06)
            }
        }
        // waves
        spawnT -= dt
        if spawnT <= 0 {
            wave += 1
            let n = 3 + min(5, wave / 2)
            let kind = wave % 5 == 0 ? 2 : wave % 2
            let baseY = CGFloat(6 + rng.next(18))
            for i in 0..<(kind == 2 ? 1 : n) {
                foes.append(Foe(p: CGPoint(x: width + 10 + CGFloat(i) * 24, y: baseY), baseY: baseY, kind: kind, hp: kind == 2 ? 14 + wave : 1 + (kind == 1 ? 1 : 0),
                                phase: Double(i) * 0.6, fireT: t + 1 + Double(rng.next(20)) / 10))
            }
            spawnT = max(1.4, 3.2 - Double(wave) * 0.08)
        }
        for i in foes.indices {
            var f = foes[i]
            let sp: CGFloat = f.kind == 2 ? 30 : f.kind == 1 ? 70 + CGFloat(wave) * 2 : 90 + CGFloat(wave) * 3
            if f.kind == 2, f.p.x < width - 120 { f.p.x = width - 120 } else { f.p.x -= sp * fdt }
            let amp: CGFloat = f.kind == 0 ? 7 : f.kind == 1 ? 3 : 9
            f.p.y = max(4, min(26, f.baseY + amp * CGFloat(sin(t * (f.kind == 2 ? 1.2 : 3) + f.phase))))
            if t > f.fireT, f.p.x < width - 20, f.p.x > ship.x + 40 {
                f.fireT = t + (f.kind == 2 ? 0.5 : 2.2 - min(1.2, Double(wave) * 0.05))
                let d = CGPoint(x: ship.x - f.p.x, y: ship.y - f.p.y); let l = max(1, hypot(d.x, d.y))
                let s: CGFloat = f.kind == 2 ? 140 : 110
                if f.kind == 2 { for a in [-0.2, 0, 0.2] as [CGFloat] { shots.append(Shot(p: f.p, v: CGPoint(x: -s * cos(a), y: s * sin(a) + d.y / l * 30), enemy: true)) } }
                else if f.kind == 1 { shots.append(Shot(p: f.p, v: CGPoint(x: d.x / l * s, y: d.y / l * s), enemy: true)) }
            }
            foes[i] = f
        }
        foes.removeAll { $0.p.x < -20 }
        for i in shots.indices { shots[i].p.x += shots[i].v.x * fdt; shots[i].p.y += shots[i].v.y * fdt }
        var deadShots = Set<Int>()
        for (si, s) in shots.enumerated() where !s.enemy {
            if let fi = foes.firstIndex(where: { abs($0.p.x - s.p.x) < ($0.kind == 2 ? 10 : 6) && abs($0.p.y - s.p.y) < ($0.kind == 2 ? 7 : 4) }) {
                deadShots.insert(si)
                foes[fi].hp -= 1; foes[fi].hitT = t
                particles.burst(x: s.p.x, y: s.p.y, count: 3, colors: [NSColor(hex: "#9ff3ff"), .white], speed: 40, life: 0.2, size: 1, gravity: 0, kind: .streak, drag: 5)
                if foes[fi].hp <= 0 { kill(fi) }
            }
        }
        for (si, s) in shots.enumerated() where s.enemy && invuln <= 0 {
            if abs(s.p.x - ship.x) < 5, abs(s.p.y - ship.y) < 2.6 { deadShots.insert(si); hurt(); break }
        }
        if invuln <= 0, let fi = foes.firstIndex(where: { abs($0.p.x - ship.x) < 8 && abs($0.p.y - ship.y) < 4 }) { kill(fi); hurt() }
        shots = shots.enumerated().filter { !deadShots.contains($0.offset) && ($0.element.enemy || $0.element.p.x < ship.x + 380) && $0.element.p.x > -10 && $0.element.p.x < width + 20 && $0.element.p.y > -5 && $0.element.p.y < 35 }.map { $0.element }
        for i in drops.indices { drops[i].p.x -= 40 * fdt }
        drops.removeAll { d in
            if abs(d.p.x - ship.x) < 8, abs(d.p.y - ship.y) < 6 {
                power = min(3, power + 1); score += 50; pulse = 1
                particles.ring(x: ship.x, y: ship.y, color: NSColor(hex: "#3ddc84"), radius: 14)
                pops.append(.init(x: ship.x, y: ship.y + 5, text: power == 3 ? "MAX POWER" : "POWER UP", color: NSColor(hex: "#3ddc84")))
                return true
            }
            return d.p.x < -10
        }
    }

    private func kill(_ fi: Int) {
        let f = foes[fi]
        let boss = f.kind == 2
        let pts = boss ? 500 : f.kind == 1 ? 40 : 20
        score += pts; pulse = 1
        let col = boss ? NSColor(hex: "#ff4fd8") : f.kind == 1 ? NSColor(hex: "#ff9f1c") : NSColor(hex: "#ff4d6d")
        particles.burst(x: f.p.x, y: f.p.y, count: boss ? 50 : 16, colors: [col, NSColor(hex: "#ffd23f"), .white], speed: boss ? 120 : 75, life: boss ? 1 : 0.5,
                        size: boss ? 2.2 : 1.6, gravity: 0, kind: .shard, drag: 2.5)
        particles.flash(x: f.p.x, y: f.p.y, color: col, radius: boss ? 40 : 12, life: boss ? 0.3 : 0.12)
        particles.ring(x: f.p.x, y: f.p.y, color: col, radius: boss ? 30 : 10)
        shake.add(boss ? 0.9 : 0.18); hitStop = boss ? 0.12 : 0.02
        pops.append(.init(x: f.p.x, y: f.p.y + 4, text: "+\(pts)", color: boss ? NSColor(hex: "#ffd23f") : .white))
        if boss || rng.next(14) == 0 { drops.append(Drop(p: f.p)) }
        foes.remove(at: fi)
    }

    private func hurt() {
        lives -= 1; invuln = 2; power = max(1, power - 1)
        shake.add(0.8); hitStop = 0.08
        particles.flash(x: ship.x, y: ship.y, color: NSColor(hex: "#ff4d6d"), radius: 30, life: 0.2)
        particles.burst(x: ship.x, y: ship.y, count: 24, colors: [NSColor(hex: "#9ff3ff"), NSColor(hex: "#ff4d6d"), .white], speed: 90, life: 0.7, size: 1.6, gravity: 0, kind: .shard, drag: 2)
        if lives <= 0 { state = .dead; stateT = t; newBest = HighScores.submit(id, score) }
    }

    public func draw(_ c: Canvas) {
        width = c.width
        c.gradient(c.bounds, [NSColor(hex: "#1a0b3a"), NSColor(hex: "#040210")])
        Glow.radial(c, CGPoint(x: c.width * 0.62 - scroll * 0.02, y: 18), 90, NSColor(hex: "#5b2bff"), alpha: 0.25)
        Glow.radial(c, CGPoint(x: c.width * 0.3 - scroll * 0.015, y: 6), 70, NSColor(hex: "#ff2bb4"), alpha: 0.14)
        for layer in 0..<3 {
            let sp = CGFloat(layer + 1) * 0.35
            let count = 70 - layer * 15
            for i in 0..<count {
                let base = CGFloat((i * 7919 + layer * 131) % 2000) / 2000 * (c.width + 20)
                var x = (base - scroll * sp).truncatingRemainder(dividingBy: c.width + 20); if x < 0 { x += c.width + 20 }
                let y = CGFloat((i * 104729 + layer * 17) % 300) / 10
                let len = CGFloat(layer) * 1.5 + 0.6
                c.fill(CGRect(x: x, y: y, width: len, height: 0.5 + CGFloat(layer) * 0.15), NSColor(white: 1, alpha: 0.25 + CGFloat(layer) * 0.2))
            }
        }
        c.cg.saveGState()
        shake.apply(c)
        for d in drops {
            Glow.radial(c, d.p, 8, NSColor(hex: "#3ddc84"), alpha: 0.6)
            Icons.star(c, d.p, 3.2, NSColor(hex: "#3ddc84"), rotation: CGFloat(t * 3))
            c.text("P", x: d.p.x, y: d.p.y - 2.6, size: 4.5, color: Arcade.ink, weight: .black, align: .center)
        }
        for f in foes { drawFoe(c, f) }
        for s in shots {
            if s.enemy {
                Glow.radial(c, s.p, 4, NSColor(hex: "#ff4fd8"), alpha: 0.7)
                c.circle(center: s.p, radius: 1.2, NSColor(hex: "#ffd0f4"))
            } else {
                let r = CGRect(x: s.p.x - 5, y: s.p.y - 0.5, width: 7, height: 1)
                Glow.capsule(c, r, NSColor(hex: "#3df5ff"), halo: 1.5, intensity: 0.5)
                c.roundRect(r, radius: 0.5, fill: NSColor(hex: "#e6fdff"))
            }
        }
        if state == .playing, invuln <= 0 || Int(t * 16) % 2 == 0 { drawShip(c) }
        particles.draw(c, camX: 0)
        Arcade.draw(c, pops)
        c.cg.restoreGState()
        if let boss = foes.first(where: { $0.kind == 2 }) {
            let r = CGRect(x: c.width / 2 - 80, y: 26.5, width: 160, height: 2)
            c.roundRect(r, radius: 1, fill: NSColor(white: 0, alpha: 0.5))
            c.roundRect(CGRect(x: r.minX, y: r.minY, width: r.width * CGFloat(boss.hp) / CGFloat(14 + wave), height: 2), radius: 1, fill: NSColor(hex: "#ff4fd8"))
        }
        Glow.vignette(c, strength: 0.35)
        let powerTxt = String(repeating: "▮", count: power) + String(repeating: "▯", count: 3 - power)
        Arcade.hud(c, [.init("SCORE", "\(score)"), .init(lives: max(0, lives), color: NSColor(hex: "#3df5ff")), .init("POWER", powerTxt, color: NSColor(hex: "#3ddc84")), .init("WAVE", "\(wave)")],
                   accent: NSColor(hex: "#3df5ff"), pulse: pulse)
        switch state {
        case .title:
            drawShipAt(c, CGPoint(x: minX + 40 + CGFloat(sin(t * 2)) * 4, y: 15 + CGFloat(sin(t * 3)) * 2), flame: 1)
            Arcade.titleCard(c, age: t - stateT, title: "STARSTRIP", tagline: "waves · power-ups · elites", accent: NSColor(hex: "#3df5ff"), accent2: NSColor(hex: "#ff4fd8"),
                             hints: [("↑ ↓ ← →", "fly"), ("SPACE Z", "fire")], best: HighScores.get(id))
        case .dead:
            Arcade.overCard(c, age: t - stateT, title: "SHOT DOWN", score: score, best: HighScores.get(id), newBest: newBest, accent: NSColor(hex: "#ff4fd8"), stats: "wave \(wave)")
        case .playing: break
        }
    }

    private func drawShip(_ c: Canvas) { drawShipAt(c, ship, flame: 1 + vx / 200) }

    private func drawShipAt(_ c: Canvas, _ p: CGPoint, flame: CGFloat) {
        let tilt = max(-0.25, min(0.25, vy / 400))
        c.cg.saveGState()
        c.cg.translateBy(x: p.x, y: p.y); c.cg.rotate(by: tilt); c.cg.scaleBy(x: 1.4, y: 1.4)
        let fl = (3 + CGFloat(sin(t * 40)) * 1.2) * flame
        Glow.radial(c, CGPoint(x: -6, y: 0), 4 + fl * 0.5, NSColor(hex: "#3df5ff"), alpha: 0.7)
        c.polygon([CGPoint(x: -5, y: 1.2), CGPoint(x: -5 - fl, y: 0), CGPoint(x: -5, y: -1.2)], NSColor(hex: "#bff9ff"))
        c.polygon([CGPoint(x: -4, y: 3.8), CGPoint(x: 2, y: 1), CGPoint(x: -1, y: 0.5)], NSColor(hex: "#5b6bff"))
        c.polygon([CGPoint(x: -4, y: -3.8), CGPoint(x: 2, y: -1), CGPoint(x: -1, y: -0.5)], NSColor(hex: "#3a44c9"))
        c.polygon([CGPoint(x: -5.5, y: 1.8), CGPoint(x: 8, y: 0), CGPoint(x: -5.5, y: -1.8)], NSColor(hex: "#dfe6ff"))
        c.polygon([CGPoint(x: -5.5, y: 0), CGPoint(x: 8, y: 0), CGPoint(x: -5.5, y: -1.8)], NSColor(hex: "#9aa8d6"))
        c.circle(center: CGPoint(x: 1.5, y: 0.35), radius: 1.1, NSColor(hex: "#3df5ff"))
        c.circle(center: CGPoint(x: 1.8, y: 0.7), radius: 0.4, .white)
        c.cg.restoreGState()
    }

    private func drawFoe(_ c: Canvas, _ f: Foe) {
        let flash = t - f.hitT < 0.06
        c.cg.saveGState()
        c.cg.translateBy(x: f.p.x, y: f.p.y)
        if f.kind != 2 { c.cg.scaleBy(x: 1.3, y: 1.3) }
        switch f.kind {
        case 0:
            let body = flash ? NSColor.white : NSColor(hex: "#ff4d6d")
            Glow.radial(c, .zero, 6, NSColor(hex: "#ff4d6d"), alpha: 0.3)
            let flapY = CGFloat(sin(t * 14 + f.phase)) * 1.2
            c.polygon([CGPoint(x: 0, y: 0.5), CGPoint(x: 3, y: 3.5 + flapY), CGPoint(x: 4, y: 0)], NSColor(hex: "#b3123a"))
            c.polygon([CGPoint(x: 0, y: -0.5), CGPoint(x: 3, y: -3.5 - flapY), CGPoint(x: 4, y: 0)], NSColor(hex: "#8a0e2d"))
            c.circle(center: .zero, radius: 2.6, body)
            c.circle(center: CGPoint(x: -0.8, y: 0.3), radius: 1, NSColor(hex: "#ffe066"))
            c.circle(center: CGPoint(x: -1, y: 0.3), radius: 0.45, .black)
        case 1:
            let body = flash ? NSColor.white : NSColor(hex: "#ff9f1c")
            c.cg.rotate(by: CGFloat(t * 2 + f.phase))
            Glow.radial(c, .zero, 7, NSColor(hex: "#ff9f1c"), alpha: 0.3)
            Icons.star(c, .zero, 4.2, NSColor(hex: "#a85a00"), points: 6, inner: 0.6)
            Icons.star(c, .zero, 3.6, body, points: 6, inner: 0.6)
            c.circle(center: .zero, radius: 1.3, NSColor(hex: "#3a1d00"))
            c.circle(center: .zero, radius: 0.6, NSColor(hex: "#ff4d6d"))
        default:
            let body = flash ? NSColor.white : NSColor(hex: "#7a2bd6")
            Glow.radial(c, .zero, 16, NSColor(hex: "#ff4fd8"), alpha: 0.35)
            c.polygon([CGPoint(x: -10, y: 0), CGPoint(x: -4, y: 7), CGPoint(x: 9, y: 5), CGPoint(x: 6, y: 0), CGPoint(x: 9, y: -5), CGPoint(x: -4, y: -7)], NSColor(hex: "#3b1270"))
            c.polygon([CGPoint(x: -9, y: 0), CGPoint(x: -3.5, y: 6), CGPoint(x: 7.5, y: 4.2), CGPoint(x: 5, y: 0), CGPoint(x: 7.5, y: -4.2), CGPoint(x: -3.5, y: -6)], body)
            c.polygon([CGPoint(x: -9, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 7.5, y: -4.2), CGPoint(x: -3.5, y: -6)], NSColor(white: 0, alpha: 0.2))
            let eye = 0.6 + 0.4 * CGFloat(sin(t * 6))
            Glow.radial(c, CGPoint(x: -4, y: 0), 5, NSColor(hex: "#ff4fd8"), alpha: eye)
            c.circle(center: CGPoint(x: -4, y: 0), radius: 2, NSColor(hex: "#ffd0f4"))
        }
        c.cg.restoreGState()
    }

    private func press() {
        if demo { demo = false; start(); return }
        switch state {
        case .title: start()
        case .dead where t - stateT > 0.8: start()
        default: break
        }
    }

    public func touchBegan(_ t: StripTouch) {
        if state != .playing || demo { press(); return }
        touchY = t.y; firing = true
    }
    public func touchMoved(_ t: StripTouch) { if touchY != nil { touchY = t.y } }
    public func touchEnded(_ t: StripTouch) { touchY = nil; firing = false }
    public func keyDown(_ key: GameKey) {
        if key == .jump || key == .run || key == .action, state != .playing || demo { press(); return }
        held.insert(key)
    }
    public func keyUp(_ key: GameKey) { held.remove(key) }
}
