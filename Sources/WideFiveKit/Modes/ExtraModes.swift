import AppKit

/// Stopwatch + countdown timer. Tap the big area to start/stop, the preset chips to arm a countdown.
public final class TimerMode: StripMode {
    public let id = "timer"
    public let title = "Timer"
    public let icon = "stopwatch"
    public var isAnimated: Bool { running || presses.animating }
    public var refreshInterval: Double { 0.2 }
    private let presses = Presses<String>()
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
        presses.step(dt)
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
        let theme = c.theme
        let x0 = Metrics.contentX
        let h = c.height - 3
        let main = CGRect(x: x0, y: 1.5, width: 196, height: h)
        let fraction = countdownFrom.map { CGFloat(min(1, elapsed / $0)) } ?? 0
        c.button(main, style: running ? .tinted(theme.accent) : .plain, pressed: presses.amount("main")) { _ in
            let center = CGPoint(x: main.minX + 15, y: main.midY)
            if countdownFrom != nil {
                c.glowing(theme.accent, blur: 5, strength: running ? 0.9 : 0) {
                    c.ring(center: center, radius: 7.5, width: 2.5, fraction: 1 - fraction, color: theme.accent)
                }
            } else {
                let pulse = running ? CGFloat(0.55 + 0.45 * sin(c.time * 5)) : 1
                c.symbol(running ? "stopwatch.fill" : "stopwatch", in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18),
                         color: (running ? theme.accent : theme.dim).withAlphaComponent(pulse), pointSize: 11)
            }
            c.text(display, x: main.midX + 12, size: Metrics.Font.display - 1, color: running ? theme.text : theme.text.withAlphaComponent(0.85),
                   weight: .bold, mono: true, align: .center)
        }

        buttons = []
        var x = main.maxX + Metrics.groupGap
        let primary = running ? "Pause" : "Start"
        for label in [primary, "Lap", "Reset"] {
            let w: CGFloat = label == primary ? 78 : 64
            let r = CGRect(x: x, y: 1.5, width: w, height: h)
            let style: ButtonStyle = label == "Start" ? .filled(theme.good) : label == "Pause" ? .filled(theme.warn) : .plain
            let sym = ["Start": "play.fill", "Pause": "pause.fill", "Lap": "flag.fill", "Reset": "arrow.counterclockwise"][label] ?? ""
            c.button(r, style: style, pressed: presses.amount(label)) { fg in
                let tw = Canvas.measure(label, size: Metrics.Font.label, weight: .semibold)
                let gx = r.midX - (tw + 15) / 2
                c.symbol(sym, in: CGRect(x: gx, y: r.minY, width: 11, height: r.height), color: fg, pointSize: 9)
                c.text(label, x: gx + 15, size: Metrics.Font.label, color: fg, weight: .semibold)
            }
            buttons.append((label, r))
            x += w + Metrics.gap
        }
        chips = []
        x += Metrics.groupGap - Metrics.gap
        c.caption("Countdown", x: x, color: theme.dim)
        x += Canvas.measure("COUNTDOWN", size: Metrics.Font.caption, weight: .bold) + 12
        for (label, secs) in [("1m", 60.0), ("3m", 180.0), ("5m", 300.0), ("10m", 600.0), ("25m", 1500.0)] {
            let r = CGRect(x: x, y: 1.5, width: 44, height: h)
            let armed = countdownFrom == secs
            c.button(r, style: .tinted(theme.accent2), pressed: presses.amount(label), selected: armed) { fg in
                c.text(label, x: r.midX, size: Metrics.Font.label, color: fg, weight: .semibold, align: .center)
            }
            chips.append((label, secs, r))
            x += 44 + Metrics.gap
        }
        if !laps.isEmpty {
            let shown = laps.suffix(3)
            var lx = c.width - 8
            for (k, lap) in shown.enumerated().reversed() {
                let n = laps.count - shown.count + k + 1
                c.text(Self.short(lap), x: lx, y: 9, size: Metrics.Font.label, color: k == shown.count - 1 ? theme.text : theme.dim, weight: .medium, mono: true, align: .right)
                lx -= Canvas.measure(Self.short(lap), size: Metrics.Font.label, mono: true) + 3
                c.caption("#\(n)", x: lx, color: theme.accent2, align: .right)
                lx -= 26
                if lx < x + 10 { break }
            }
        }
    }

    private func target(_ x: CGFloat) -> String? {
        let p = CGPoint(x: x, y: 15)
        if let c = chips.first(where: { $0.2.contains(p) }) { return c.0 }
        if let b = buttons.first(where: { $0.1.contains(p) }) { return b.0 }
        return x < (buttons.first?.1.minX ?? 0) ? "main" : nil
    }

    public func touchBegan(_ t: StripTouch) { if let k = target(t.x) { presses.press(k) } }
    public func touchCancelled(_ t: StripTouch) { presses.cancelAll() }

    private static func short(_ v: Double) -> String { String(format: "%d:%05.2f", Int(v) / 60, v.truncatingRemainder(dividingBy: 60)) }

    public func touchEnded(_ t: StripTouch) {
        presses.releaseAll()
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
    private var scroller = Scroller()
    private let presses = Presses<String>()

    public var isAnimated: Bool { scroller.animating || presses.animating }

    public init() {}
    public func activate(_ ctx: ModeContext) { self.ctx = ctx }
    public func update(dt: Double) { scroller.step(dt); presses.step(dt) }

    private var ordered: [String] { recents + all.filter { !recents.contains($0) } }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        let w: CGFloat = 34, gap: CGFloat = 4
        frames = []
        let list = ordered
        let recentW: CGFloat = recents.isEmpty ? 0 : 44
        let total = recentW + CGFloat(list.count) * (w + gap) + (recents.isEmpty ? 0 : Metrics.groupGap)
        scroller.maxOffset = max(0, total - (c.width - x0))
        let off = scroller.offset
        let view = CGRect(x: x0 - 2, y: 0, width: c.width - x0 + 2, height: c.height)
        c.clip(view) {
            c.fadeEdges(view, left: off > 1 ? 20 : 0, right: off < scroller.maxOffset - 1 ? 30 : 0) {
                var x = x0 - off
                if !recents.isEmpty {
                    c.caption("Recent", x: x + recentW / 2 - 2, y: 11, color: theme.accent, align: .center)
                    x += recentW
                }
                for (i, e) in list.enumerated() {
                    if i == recents.count, !recents.isEmpty {
                        c.roundRect(CGRect(x: x + Metrics.groupGap / 2 - 2.5, y: 9, width: 1, height: 12), radius: 0.5, fill: theme.dim.withAlphaComponent(0.3))
                        x += Metrics.groupGap
                    }
                    let r = CGRect(x: x, y: 1.5, width: w, height: c.height - 3)
                    frames.append((e, r))
                    if r.maxX > view.minX, r.minX < view.maxX {
                        let p = presses.amount(e)
                        c.button(r, style: .plain, pressed: p) { _ in
                            c.scaled(1 + 0.25 * CGFloat(Ease.bump(Double(p))), around: CGPoint(x: r.midX, y: r.midY)) {
                                c.text(e, x: r.midX, y: 6, size: 17, align: .center)
                            }
                        }
                    }
                    x += w + gap
                }
            }
        }
    }

    public func touchBegan(_ t: StripTouch) {
        scroller.begin(t)
        pressed = frames.first { $0.1.contains(CGPoint(x: t.x, y: 15)) && t.x > Metrics.contentX - 2 }?.0
        if let p = pressed { presses.press(p) }
    }

    public func touchMoved(_ t: StripTouch) {
        if scroller.move(t), pressed != nil { pressed = nil; presses.cancelAll() }
    }

    public func touchEnded(_ t: StripTouch) {
        let wasScrolling = scroller.dragging
        scroller.end(t)
        if let p = pressed { presses.release(p) }
        defer { pressed = nil }
        guard !wasScrolling, let e = pressed, let ctx else { return }
        recents = ([e] + recents.filter { $0 != e }).prefix(8).map { $0 }
        UserDefaults.standard.set(recents, forKey: Self.defaultsKey)
        ctx.run(Action(type: e))
        ctx.toast("\(e)  inserted")
    }

    public func touchCancelled(_ t: StripTouch) { scroller.end(t); pressed = nil; presses.cancelAll() }
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
        let theme = c.theme
        let sky = theme.isLight ? theme.background.mix(theme.accent2, 0.12) : theme.background.mix(theme.accent2, 0.1)
        c.gradient(c.bounds, [sky, theme.backgroundTop ?? theme.background])
        // Twinkling stars (dark themes) / soft clouds (light).
        for i in 0..<22 {
            let sx = CGFloat((i * 151) % 997) / 997 * c.width
            let sy = 14 + CGFloat((i * 53) % 13)
            let tw = CGFloat(0.35 + 0.35 * sin(t * 1.3 + Double(i)))
            if theme.isLight { c.roundRect(CGRect(x: sx, y: sy + 2, width: 14, height: 3), radius: 1.5, fill: NSColor.white.withAlphaComponent(0.7)) }
            else { c.fill(CGRect(x: sx, y: sy, width: 1, height: 1), theme.text.withAlphaComponent(tw)) }
        }
        let grass = theme.good.mix(theme.background, theme.isLight ? 0.25 : 0.45)
        c.fill(CGRect(x: 0, y: 0, width: c.width, height: 2), grass.mix(.black, 0.2))
        for i in 0..<Int(c.width / 9) {
            let gx = CGFloat(i) * 9 + CGFloat((i * 7) % 5)
            let sway = CGFloat(sin(t * 1.6 + Double(i) * 0.7)) * 0.8
            c.polygon([CGPoint(x: gx, y: 1), CGPoint(x: gx + 3, y: 1), CGPoint(x: gx + 1.5 + sway, y: 3.5 + CGFloat((i * 5) % 3))], grass)
        }
        let bob = sleepy ? 0 : CGFloat(abs(sin(t * 6))) * 2
        c.sprite(happy > 0.1 ? Sprites.catHappy : (sleepy ? Sprites.catSleep : Sprites.cat), x: x, y: 2 + bob, scale: 2, flipX: dir < 0)
        if sleepy {
            for k in 0..<3 {
                let p = CGFloat(k) * 0.33 + CGFloat(t.truncatingRemainder(dividingBy: 1))
                c.text("z", x: x + 10 + p * 10, y: 12 + p * 12, size: 6 + p * 3, color: theme.text.withAlphaComponent(1 - p), weight: .bold)
            }
        }
        for (p, life) in hearts {
            c.glowing(theme.accent, blur: 5, strength: 0.8) {
                c.text("♥", x: p.x, y: p.y, size: 8 + CGFloat(1.2 - life) * 4, color: theme.accent.withAlphaComponent(CGFloat(min(1, life))), align: .center)
            }
        }
        // Status pill: mood + live CPU meter.
        let mood = sleepy ? "Napping" : (happy > 0.1 ? "Delighted" : (cpu > 0.6 ? "Stressed — your Mac is busy" : "Pottering about"))
        let moodIcon = sleepy ? "moon.zzz.fill" : (happy > 0.1 ? "heart.fill" : (cpu > 0.6 ? "flame.fill" : "pawprint.fill"))
        let tw = Canvas.measure(mood, size: Metrics.Font.label, weight: .semibold)
        let pw = tw + 128
        let pill = CGRect(x: c.width - pw - 6, y: 4, width: pw, height: c.height - 8)
        c.panel(pill, fill: theme.surface.withAlphaComponent(0.85), radius: pill.height / 2)
        let moodCol = sleepy ? theme.accent2 : (happy > 0.1 ? theme.accent : (cpu > 0.6 ? theme.bad : theme.good))
        c.symbol(moodIcon, in: CGRect(x: pill.minX + 7, y: pill.minY, width: 14, height: pill.height), color: moodCol, pointSize: 9)
        c.text(mood, x: pill.minX + 25, size: Metrics.Font.label, color: theme.text, weight: .semibold)
        let mx = pill.minX + 33 + tw
        c.caption("CPU", x: mx, color: theme.dim)
        c.meter(CGRect(x: mx + 24, y: pill.midY - 2, width: 46, height: 4), value: CGFloat(cpu), colors: [moodCol.withAlphaComponent(0.7), moodCol])
        c.text("\(Int(cpu * 100))%", x: pill.maxX - 9, size: Metrics.Font.caption + 1, color: theme.dim, weight: .semibold, mono: true, align: .right)
        c.caption("Tap to pet", x: Metrics.contentX + 2, y: 19, color: theme.dim.withAlphaComponent(0.8))
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
    private let presses = Presses<String>()
    private var bump = Smoothed(0, speed: 30)
    public var isAnimated: Bool { presses.animating || !bump.settled }

    public init() {}
    public func activate(_ ctx: ModeContext) { self.ctx = ctx }
    public func update(dt: Double) { presses.step(dt); bump.step(dt) }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        let display = CGRect(x: x0, y: 1.5, width: 170, height: c.height - 3)
        c.panel(display, fill: theme.isLight ? theme.surface : theme.background.mix(theme.surface, 0.6))
        if let op {
            c.text("\(format(accumulator ?? 0)) \(op)", x: display.minX + 8, y: 9.5, size: Metrics.Font.caption + 0.5, color: theme.dim,
                   weight: .semibold, mono: true, maxWidth: 70)
        }
        let s = 1 + 0.06 * CGFloat(bump.value)
        c.scaled(s, around: CGPoint(x: display.maxX - 8, y: display.midY)) {
            c.text(entry, x: display.maxX - 9, size: Metrics.Font.display - 2, color: theme.text, weight: .semibold, mono: true, align: .right,
                   maxWidth: display.width - (op == nil ? 14 : 80))
        }
        frames = []
        let gap: CGFloat = 4
        let groupBreaks: Set<Int> = [4, 8, 12, 16]
        let avail = c.width - display.maxX - Metrics.groupGap - 4 - gap * CGFloat(keys.count - 1) - CGFloat(groupBreaks.count) * 4
        let w = min(44, avail / CGFloat(keys.count))
        var x = display.maxX + Metrics.groupGap
        for (i, k) in keys.enumerated() {
            if groupBreaks.contains(i) { x += 4 }
            let r = CGRect(x: x, y: 1.5, width: w, height: c.height - 3)
            frames.append((k, r))
            let style: ButtonStyle
            switch k {
            case "=": style = .filled(theme.accent)
            case "÷", "×", "−", "+": style = .tinted(theme.accent2)
            case "C", "⌫": style = .tinted(theme.bad)
            case "%", "±": style = .tinted(theme.dim)
            default: style = .plain
            }
            c.button(r, style: style, pressed: presses.amount(k), selected: op == k && replaceEntry) { fg in
                let isDigit = Int(k) != nil || k == "."
                c.text(k, x: r.midX, size: isDigit ? 14 : 13.5, color: isDigit ? theme.text : fg, weight: isDigit ? .medium : .semibold, align: .center)
            }
            x += w + gap
        }
    }

    public func touchBegan(_ t: StripTouch) {
        pressed = frames.first { $0.1.insetBy(dx: -2, dy: 0).contains(CGPoint(x: t.x, y: 15)) }?.0
        if let p = pressed { presses.press(p) }
    }

    public func touchEnded(_ t: StripTouch) {
        if let p = pressed { presses.release(p) }
        defer { pressed = nil }
        guard let k = pressed, frames.first(where: { $0.0 == k })?.1.insetBy(dx: -2, dy: 0).contains(CGPoint(x: t.x, y: 15)) == true else { return }
        press(k)
        bump.value = 1; bump.target = 0
    }

    public func touchCancelled(_ t: StripTouch) { pressed = nil; presses.cancelAll() }

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
