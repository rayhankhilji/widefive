import AppKit

/// Stopwatch + countdown timer. Tap the big area to start/stop, the preset chips to arm a countdown.
public final class TimerMode: StripMode {
    public let id = "timer"
    public let title = "Timer"
    public let icon = "stopwatch"
    public var isAnimated: Bool { running }
    public var refreshInterval: Double { 0.2 }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private var ctx: ModeContext?
    private var elapsed = 0.0
    private var countdownFrom: Double?
    private var running = false
    private var laps: [Double] = []
    private var chips: [(String, Double, CGRect)] = []
    private var buttons: [(String, CGRect)] = []
    private var fired = false

    public init() {}
    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    public func update(dt: Double) {
        guard running else { return }
        elapsed += dt
        if let from = countdownFrom, elapsed >= from, !fired {
            fired = true; running = false; elapsed = from
            NSSound(named: "Glass")?.play()
            ctx?.toast("⏰ timer done")
        }
    }

    private var display: String {
        let v = countdownFrom.map { max(0, $0 - elapsed) } ?? elapsed
        let m = Int(v) / 60, s = Int(v) % 60, cs = Int(v * 100) % 100
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    public func draw(_ c: Canvas) {
        c.clear(c.theme.background)
        let x0 = StripController.exitWidth + 6
        let main = CGRect(x: x0, y: 1, width: 210, height: 28)
        let fraction = countdownFrom.map { CGFloat(min(1, elapsed / $0)) } ?? 0
        c.roundRect(main, radius: 7, fill: c.theme.button)
        if countdownFrom != nil {
            c.roundRect(CGRect(x: main.minX, y: main.minY, width: main.width * fraction, height: main.height), radius: 7,
                        fill: c.theme.accent.withAlphaComponent(0.35))
        }
        c.text(display, x: main.midX, size: 17, color: running ? c.theme.accent : c.theme.text, weight: .heavy, mono: true, align: .center)

        buttons = []
        var x = main.maxX + 6
        for label in [running ? "Pause" : "Start", "Lap", "Reset"] {
            let w: CGFloat = 70
            let r = CGRect(x: x, y: 1, width: w, height: 28)
            c.roundRect(r, radius: 7, fill: label == "Start" ? c.theme.accent : c.theme.button)
            c.text(label, x: r.midX, size: 11, color: label == "Start" ? .black : c.theme.text, weight: .semibold, align: .center)
            buttons.append((label, r))
            x += w + 5
        }
        chips = []
        x += 6
        for (label, secs) in [("1m", 60.0), ("3m", 180.0), ("5m", 300.0), ("10m", 600.0), ("25m", 1500.0)] {
            let r = CGRect(x: x, y: 1, width: 48, height: 28)
            let armed = countdownFrom == secs
            c.roundRect(r, radius: 7, fill: armed ? c.theme.accent2 : c.theme.button)
            c.text(label, x: r.midX, size: 11, color: armed ? .black : c.theme.text, weight: .semibold, align: .center)
            chips.append((label, secs, r))
            x += 53
        }
        if !laps.isEmpty {
            let text = laps.suffix(4).enumerated().map { "#\(laps.count - min(4, laps.count) + $0.offset + 1) \(Self.short($0.element))" }.joined(separator: "   ")
            c.text(text, x: c.width - 8, size: 10, color: c.theme.dim, mono: true, align: .right, maxWidth: c.width - x - 10)
        }
    }

    private static func short(_ v: Double) -> String { String(format: "%d:%05.2f", Int(v) / 60, v.truncatingRemainder(dividingBy: 60)) }

    public func touchEnded(_ t: StripTouch) {
        if let chip = chips.first(where: { $0.2.contains(CGPoint(x: t.x, y: 15)) }) {
            countdownFrom = countdownFrom == chip.1 ? nil : chip.1
            elapsed = 0; fired = false; running = false
            return
        }
        guard let b = buttons.first(where: { $0.1.contains(CGPoint(x: t.x, y: 15)) }) else {
            running.toggle(); return
        }
        switch b.0 {
        case "Lap": if running { laps.append(elapsed) }
        case "Reset": running = false; elapsed = 0; laps = []; fired = false
        default: running.toggle(); fired = false
        }
    }
}

/// Emoji strip: tap to paste one into whatever you're typing in. Recents float to the front.
public final class EmojiMode: StripMode {
    public let id = "emoji"
    public let title = "Emoji"
    public let icon = "face.smiling"
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private static let defaultsKey = "widefive.emoji.recents"
    private let all = ["😂","🔥","💀","✅","❌","🙏","👀","🚀","💯","🤝","😅","🧠","⚡️","🎯","🥲","👍","👎","❤️","🤔","😭","🙌","✨","🐛","🛠️","📦","⏰","☕️","🍻","😎","🤷","🎉","💡","🧊","🌙","📈","🔒"]
    private var recents: [String] = UserDefaults.standard.stringArray(forKey: EmojiMode.defaultsKey) ?? []
    private var frames: [(String, CGRect)] = []
    private var ctx: ModeContext?
    private var pressed: String?
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var scrolling = false
    private var contentWidth: CGFloat = 0

    public init() {}
    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    private var ordered: [String] { recents + all.filter { !recents.contains($0) } }

    public func draw(_ c: Canvas) {
        let x0 = StripController.exitWidth + 4
        c.clear(c.theme.background)
        frames = []
        var x = x0 - offset
        for e in ordered {
            let r = CGRect(x: x, y: 1, width: 34, height: 28)
            frames.append((e, r))
            if r.maxX > x0, r.minX < c.width {
                c.roundRect(r, radius: 6, fill: pressed == e ? c.theme.accent : c.theme.button)
                c.text(e, x: r.midX, y: 6, size: 17, align: .center)
            }
            x += 37
        }
        contentWidth = x + offset - x0
        c.clip(CGRect(x: 0, y: 0, width: x0, height: 30)) { c.fill(CGRect(x: 0, y: 0, width: x0, height: 30), c.theme.background) }
    }

    public func touchBegan(_ t: StripTouch) {
        pressed = frames.first { $0.1.contains(CGPoint(x: t.x, y: 15)) }?.0
        startOffset = offset
        scrolling = false
    }

    public func touchMoved(_ t: StripTouch) {
        guard abs(t.dx) > 8 else { return }
        scrolling = true
        pressed = nil
        offset = max(0, min(max(0, contentWidth - 300), startOffset - t.dx))
    }

    public func touchEnded(_ t: StripTouch) {
        defer { pressed = nil }
        guard !scrolling, let e = pressed, let ctx else { return }
        recents = ([e] + recents.filter { $0 != e }).prefix(8).map { $0 }
        UserDefaults.standard.set(recents, forKey: Self.defaultsKey)
        ctx.run(Action(type: e))
        ctx.toast("\(e) inserted")
    }
}

/// A pixel pet that lives in the strip and reacts to how hard your Mac is working.
public final class PetMode: StripMode {
    public let id = "pet"
    public let title = "Pet"
    public let icon = "pawprint.fill"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }

    private var x: CGFloat = 200
    private var dir: CGFloat = 1
    private var t = 0.0
    private var happy = 0.0
    private var hearts: [(CGPoint, Double)] = []
    private var sleepy = false

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    public func update(dt: Double) {
        t += dt
        happy = max(0, happy - dt * 0.2)
        let cpu = Stats.shared.cpu
        sleepy = cpu < 0.08 && happy <= 0
        let speed: CGFloat = sleepy ? 0 : CGFloat(16 + cpu * 90 + happy * 40)
        x += dir * speed * CGFloat(dt)
        if x < 30 { x = 30; dir = 1 }
        hearts = hearts.compactMap { ($0.0.applying(CGAffineTransform(translationX: 0, y: CGFloat(dt) * 10)), $0.1 - dt) }.filter { $0.1 > 0 }
    }

    public func draw(_ c: Canvas) {
        if x > c.width - 30 { x = c.width - 30; dir = -1 }
        let cpu = Stats.shared.cpu
        c.gradient(c.bounds, [NSColor(hex: "#101828"), NSColor(hex: "#1d2b4a")])
        for i in 0..<28 {
            let gx = CGFloat(i) * (c.width / 28)
            c.fill(CGRect(x: gx, y: 0, width: 6, height: 2 + CGFloat((i * 7) % 4)), NSColor(hex: "#2f7a4a"))
        }
        let bob = sleepy ? 0 : CGFloat(abs(sin(t * 6))) * 2
        c.sprite(happy > 0.1 ? Sprites.catHappy : (sleepy ? Sprites.catSleep : Sprites.cat), x: x, y: 2 + bob, scale: 2, flipX: dir < 0)
        if sleepy {
            for k in 0..<3 {
                let p = CGFloat(k) * 0.33 + CGFloat(t.truncatingRemainder(dividingBy: 1))
                c.text("z", x: x + 10 + p * 10, y: 12 + p * 12, size: 6 + p * 3, color: NSColor(white: 1, alpha: 1 - p))
            }
        }
        for (p, life) in hearts { c.text("♥", x: p.x, y: p.y, size: 8, color: Pal.pink.withAlphaComponent(CGFloat(life)), align: .center) }
        let mood = sleepy ? "napping" : (happy > 0.1 ? "delighted" : (cpu > 0.6 ? "stressed — your Mac is busy" : "pottering about"))
        c.text("\(mood)   cpu \(Int(cpu * 100))%", x: c.width - 8, y: 11, size: 9, color: c.theme.dim, mono: true, align: .right)
        c.text("tap to pet", x: StripController.exitWidth + 8, y: 11, size: 9, color: c.theme.dim)
    }

    public func touchBegan(_ t: StripTouch) {
        happy = 3
        hearts.append((CGPoint(x: t.x, y: 16), 1.2))
    }
}

/// A calculator that finally has room for all its buttons.
public final class CalculatorMode: StripMode {
    public let id = "calc"
    public let title = "Calculator"
    public let icon = "function"
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private let keys = ["7","8","9","÷","4","5","6","×","1","2","3","−","0",".","=","+","C","⌫","%","±"]
    private var frames: [(String, CGRect)] = []
    private var pressed: String?
    private var entry = "0"
    private var accumulator: Double?
    private var op: String?
    private var replaceEntry = true
    private var ctx: ModeContext?

    public init() {}
    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    public func draw(_ c: Canvas) {
        c.clear(c.theme.background)
        let x0 = StripController.exitWidth + 4
        let display = CGRect(x: x0, y: 1, width: 150, height: 28)
        c.roundRect(display, radius: 7, fill: c.theme.button)
        c.text(entry, x: display.maxX - 8, size: 15, color: c.theme.accent, weight: .heavy, mono: true, align: .right, maxWidth: display.width - 12)
        frames = []
        let avail = c.width - display.maxX - 10
        let w = min(44, avail / CGFloat(keys.count) - 4)
        var x = display.maxX + 6
        for k in keys {
            let r = CGRect(x: x, y: 1, width: w, height: 28)
            frames.append((k, r))
            let isOp = "÷×−+=".contains(k)
            let fill = pressed == k ? c.theme.accent : (isOp ? c.theme.accent2.withAlphaComponent(0.6) : c.theme.button)
            c.roundRect(r, radius: 6, fill: fill)
            c.text(k, x: r.midX, size: 13, color: pressed == k ? .black : c.theme.text, weight: .semibold, align: .center)
            x += w + 4
        }
    }

    public func touchBegan(_ t: StripTouch) { pressed = frames.first { $0.1.contains(CGPoint(x: t.x, y: 15)) }?.0 }

    public func touchEnded(_ t: StripTouch) {
        defer { pressed = nil }
        guard let k = pressed, frames.first(where: { $0.0 == k })?.1.contains(CGPoint(x: t.x, y: 15)) == true else { return }
        press(k)
    }

    private var value: Double { Double(entry) ?? 0 }

    private func press(_ k: String) {
        switch k {
        case "0"..."9":
            entry = replaceEntry || entry == "0" ? k : entry + k
            replaceEntry = false
        case ".":
            if replaceEntry { entry = "0."; replaceEntry = false } else if !entry.contains(".") { entry += "." }
        case "C": entry = "0"; accumulator = nil; op = nil; replaceEntry = true
        case "⌫": entry = String(entry.dropLast()); if entry.isEmpty || entry == "-" { entry = "0" }
        case "±": entry = entry.hasPrefix("-") ? String(entry.dropFirst()) : "-" + entry
        case "%": entry = format(value / 100); replaceEntry = true
        case "=":
            entry = format(apply())
            accumulator = nil; op = nil; replaceEntry = true
            ctx?.toast("= \(entry) (long-press-free: tap C to clear)")
        default:
            let result = apply()
            accumulator = result
            entry = format(result)
            op = k
            replaceEntry = true
        }
    }

    private func apply() -> Double {
        guard let a = accumulator, let o = op else { return value }
        switch o {
        case "+": return a + value
        case "−": return a - value
        case "×": return a * value
        case "÷": return value == 0 ? Double.nan : a / value
        default: return value
        }
    }

    private func format(_ d: Double) -> String {
        if d.isNaN || d.isInfinite { return "error" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(format: "%.6g", d)
    }
}
