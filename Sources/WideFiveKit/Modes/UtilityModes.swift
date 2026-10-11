import AppKit

/// Clipboard history chips. Tap → copy back. Long-press → copy & paste into the frontmost app. Drag to scroll.
public final class ClipboardMode: StripMode {
    public let id = "clipboard"
    public let title = "Clipboard"
    public let icon = "doc.on.clipboard"
    public var refreshInterval: Double { 0.5 }
    public var showsExitButton: Bool { true }

    private var history: [String] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var frames: [CGRect] = []
    private var pressed: Int?
    private var scroller = Scroller()
    private var scrolling: Bool { scroller.dragging }
    private let presses = Presses<Int>()
    private var longFired = false
    private var work: DispatchWorkItem?
    private var ctx: ModeContext?
    private static let shared = ClipboardWatcher.shared

    public var isAnimated: Bool { scroller.animating || presses.animating }

    public init() { ClipboardWatcher.shared.start() }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx }
    public func update(dt: Double) { scroller.step(dt); presses.step(dt) }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        history = ClipboardWatcher.shared.items
        let x0 = Metrics.contentX
        frames = []
        if history.isEmpty {
            let r = CGRect(x: x0, y: 1.5, width: 26, height: c.height - 3)
            c.panel(r)
            c.symbol("doc.on.clipboard", in: r, color: theme.accent, pointSize: Metrics.iconSmall)
            c.text("Copy something — it’ll show up here", x: r.maxX + 10, size: Metrics.Font.body, color: theme.text, weight: .medium)
            let tw = Canvas.measure("Copy something — it’ll show up here", size: Metrics.Font.body, weight: .medium)
            c.caption("Passwords from managers are ignored", x: r.maxX + 22 + tw)
            return
        }
        let labels = history.map { $0.replacingOccurrences(of: "\n", with: " ⏎ ").trimmingCharacters(in: .whitespaces) }
        let widths = labels.map { min(230, Canvas.measure($0, size: Metrics.Font.label + 0.5) + 36) }
        let total = widths.reduce(0) { $0 + $1 + Metrics.gap }
        scroller.maxOffset = max(0, total - (c.width - x0))
        let off = scroller.offset
        let view = CGRect(x: x0 - 2, y: 0, width: c.width - x0 + 2, height: c.height)
        c.clip(view) {
            c.fadeEdges(view, left: off > 1 ? 20 : 0, right: off < scroller.maxOffset - 1 ? 30 : 0) {
                var x = x0 - off
                for (i, label) in labels.enumerated() {
                    let w = widths[i]
                    let r = CGRect(x: x, y: 1.5, width: w, height: c.height - 3)
                    frames.append(r)
                    if r.maxX > view.minX, r.minX < view.maxX {
                        c.button(r, style: .plain, pressed: presses.amount(i)) { fg in
                            let badge = CGRect(x: r.minX + 5, y: r.midY - 7, width: 14, height: 14)
                            c.roundRect(badge, radius: 7, fill: i == 0 ? theme.accent : theme.accent.withAlphaComponent(theme.isLight ? 0.14 : 0.2))
                            c.text("\(i + 1)", x: badge.midX, y: badge.minY + 2.5, size: 8, color: i == 0 ? theme.onAccent : theme.accent, weight: .bold, align: .center)
                            c.text(label, x: badge.maxX + 7, size: Metrics.Font.label + 0.5, color: fg, maxWidth: r.maxX - badge.maxX - 13)
                        }
                    }
                    x += w + Metrics.gap
                }
            }
        }
    }

    private func hit(_ x: CGFloat) -> Int? { frames.firstIndex { $0.minX <= x && x <= $0.maxX } }

    public func touchBegan(_ t: StripTouch) {
        pressed = hit(t.x); longFired = false
        scroller.begin(t)
        work?.cancel()
        guard let i = pressed else { return }
        presses.press(i)
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == i, !self.scrolling, i < self.history.count else { return }
            self.longFired = true
            ClipboardWatcher.shared.copy(self.history[i])
            Keys.sendChord("cmd+v")
            self.ctx?.toast("Pasted")
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    public func touchMoved(_ t: StripTouch) {
        if scroller.move(t), pressed != nil { pressed = nil; presses.cancelAll(); work?.cancel() }
    }

    public func touchCancelled(_ t: StripTouch) { work?.cancel(); scroller.end(t); pressed = nil; presses.cancelAll() }

    public func touchEnded(_ t: StripTouch) {
        work?.cancel()
        let wasScrolling = scrolling
        scroller.end(t)
        if let p = pressed { presses.release(p) }
        defer { pressed = nil }
        guard let i = pressed, !wasScrolling, !longFired, i < history.count else { return }
        ClipboardWatcher.shared.copy(history[i])
        ctx?.toast("Copied  “\(history[i].prefix(40))”")
    }
}

final class ClipboardWatcher {
    static let shared = ClipboardWatcher()
    private(set) var items: [String] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var ignoreNext = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(String(s.prefix(2000)), at: 0)
        if items.count > 20 { items.removeLast() }
    }

    func copy(_ s: String) {
        ignoreNext = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Running apps as a mini-dock. Tap → activate, long-press → hide.
public final class DockMode: StripMode {
    public let id = "dock"
    public let title = "Dock"
    public let icon = "dock.rectangle"
    public var refreshInterval: Double { 1 }
    public var showsExitButton: Bool { true }
    private var apps: [NSRunningApplication] = []
    private var frames: [CGRect] = []
    private var pressed: Int?
    private var work: DispatchWorkItem?
    private var longFired = false
    private let presses = Presses<Int>()
    private var refresh = 0.0

    public var isAnimated: Bool { presses.animating }

    public init() {}

    public func update(dt: Double) {
        presses.step(dt)
        refresh -= dt
        guard refresh <= 0 || apps.isEmpty else { return }
        refresh = 1
        apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    public func activate(_ ctx: ModeContext) { refresh = 0; update(dt: 0) }

    public func draw(_ c: Canvas) {
        let theme = c.theme
        let x0 = Metrics.contentX
        let w: CGFloat = 38
        frames = []
        let front = NSWorkspace.shared.frontmostApplication
        if apps.isEmpty { c.caption("No running apps", x: x0 + 4); return }
        // Subtle shelf behind the icons, like the real Dock.
        let count = CGFloat(apps.count)
        let shelfW = min(c.width - x0 - 4, count * (w + 4) + 6)
        c.panel(CGRect(x: x0 - 3, y: 1, width: shelfW, height: c.height - 2), fill: theme.surface.withAlphaComponent(theme.isLight ? 0.7 : 0.55))
        for (i, app) in apps.enumerated() {
            let r = CGRect(x: x0 + CGFloat(i) * (w + 4), y: 0, width: w, height: 30)
            guard r.maxX < c.width - 4 else { break }
            frames.append(r)
            let p = presses.amount(i)
            let isFront = app == front
            if isFront { c.panel(r.insetBy(dx: 0, dy: 2.5), fill: theme.surfaceHi.withAlphaComponent(0.8), sheen: false) }
            let s = 1 - 0.12 * p
            if let icon = app.icon {
                c.scaled(s, around: CGPoint(x: r.midX, y: 15)) {
                    c.faded(app.isHidden ? 0.45 : 1) { c.image(icon, in: CGRect(x: r.midX - 11.5, y: 4, width: 23, height: 23)) }
                }
            }
            if !app.isHidden {
                c.glowing(theme.accent, blur: 4, strength: isFront ? 1 : 0) {
                    c.circle(center: CGPoint(x: r.midX, y: 2), radius: isFront ? 1.4 : 1, isFront ? theme.accent : theme.dim)
                }
            }
        }
    }

    private func hit(_ x: CGFloat) -> Int? { frames.firstIndex { $0.minX <= x && x <= $0.maxX } }

    public func touchBegan(_ t: StripTouch) {
        pressed = hit(t.x); longFired = false
        work?.cancel()
        guard let i = pressed, i < apps.count else { return }
        presses.press(i)
        let app = apps[i]
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == i else { return }
            self.longFired = true
            app.hide()
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    public func touchEnded(_ t: StripTouch) {
        work?.cancel()
        if let p = pressed { presses.release(p) }
        defer { pressed = nil }
        guard let i = pressed, !longFired, i < apps.count, abs(t.dx) < 20 else { return }
        if #available(macOS 14.0, *) { apps[i].activate() } else { apps[i].activate(options: [.activateIgnoringOtherApps]) }
    }
}

/// Full-width system dashboard.
public final class StatsMode: StripMode {
    public let id = "stats"
    public let title = "Stats"
    public let icon = "chart.xyaxis.line"
    public var refreshInterval: Double { 0.5 }
    public var showsExitButton: Bool { true }

    public init() {}
    public func activate(_ ctx: ModeContext) {}

    public func draw(_ c: Canvas) {
        let s = Stats.shared
        let theme = c.theme
        let x0 = Metrics.contentX
        let avail = c.width - x0 - 2
        let sections: [(String, CGFloat)] = [("cpu", 0.27), ("ram", 0.17), ("net", 0.2), ("temp", 0.12), ("bat", 0.12), ("disk", 0.12)]
        var x = x0
        let gap = Metrics.gap
        for (name, frac) in sections {
            let r = CGRect(x: x, y: 1.5, width: avail * frac - gap, height: c.height - 3)
            x += avail * frac
            c.panel(r)
            let big = Metrics.Font.title
            switch name {
            case "cpu":
                c.clip(r.insetBy(dx: 1, dy: 1)) { sparkline(c, s.cpuHistory, in: r.insetBy(dx: 1, dy: 2), color: meterColor(c, s.cpu), maxValue: 1) }
                c.caption("CPU", x: r.minX + 9)
                c.text("\(Int(s.cpu * 100))%", x: r.maxX - 9, size: big, color: theme.text, weight: .bold, mono: true, align: .right)
            case "ram":
                let f = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
                c.caption("Memory", x: r.minX + 9, y: 15.5)
                c.meter(CGRect(x: r.minX + 9, y: 7, width: r.width * 0.42, height: 4), value: CGFloat(f), colors: [meterColor(c, f).withAlphaComponent(0.7), meterColor(c, f)])
                c.text(Stats.bytes(s.memUsed), x: r.maxX - 9, y: 13, size: Metrics.Font.body, color: theme.text, weight: .semibold, mono: true, align: .right)
                c.text("of " + Stats.bytes(s.memTotal), x: r.maxX - 9, y: 3, size: Metrics.Font.caption, color: theme.dim, mono: true, align: .right)
            case "net":
                c.clip(r.insetBy(dx: 1, dy: 1)) { sparkline(c, s.netHistory, in: r.insetBy(dx: 1, dy: 2), color: theme.accent2) }
                c.caption("Network", x: r.minX + 9)
                c.text("↓ " + Stats.bytes(s.netDown, perSec: true), x: r.maxX - 9, y: 14, size: Metrics.Font.label, color: theme.text, weight: .semibold, mono: true, align: .right)
                c.text("↑ " + Stats.bytes(s.netUp, perSec: true), x: r.maxX - 9, y: 3, size: Metrics.Font.label - 1, color: theme.dim, mono: true, align: .right)
            case "temp":
                let t = s.temperature
                let col = (t ?? 0) < 60 ? theme.good : (t ?? 0) < 85 ? theme.warn : theme.bad
                c.symbol("thermometer.medium", in: CGRect(x: r.minX + 5, y: r.minY, width: 16, height: r.height), color: t == nil ? theme.dim : col, pointSize: 11)
                c.text(t.map { "\(Int($0))°" } ?? "—", x: r.maxX - 9, y: 13, size: Metrics.Font.body, color: theme.text, weight: .bold, mono: true, align: .right)
                c.text(s.fan.map { "\(Int($0)) rpm" } ?? "no sensor", x: r.maxX - 9, y: 3, size: Metrics.Font.caption, color: theme.dim, mono: true, align: .right)
            case "bat":
                let b = s.battery
                let col = s.charging ? theme.good : ((b ?? 1) < 0.2 ? theme.bad : theme.accent)
                c.ring(center: CGPoint(x: r.minX + 15, y: r.midY), radius: 7, width: 2.5, fraction: CGFloat(b ?? 1), color: col)
                if s.charging || b == nil { c.symbol(b == nil ? "powerplug.fill" : "bolt.fill", in: CGRect(x: r.minX + 9, y: r.midY - 6, width: 12, height: 12), color: col, pointSize: 6.5) }
                c.text(b.map { "\(Int($0 * 100))%" } ?? "AC", x: r.maxX - 9, y: 13, size: Metrics.Font.body, color: theme.text, weight: .bold, mono: true, align: .right)
                c.text(s.charging ? "charging" : (b == nil ? "power" : "battery"), x: r.maxX - 9, y: 3, size: Metrics.Font.caption, color: theme.dim, align: .right)
            default:
                c.symbol("internaldrive.fill", in: CGRect(x: r.minX + 5, y: r.minY, width: 18, height: r.height), color: theme.accent2, pointSize: 11)
                c.text(Stats.bytes(s.diskFree), x: r.maxX - 9, y: 13, size: Metrics.Font.body, color: theme.text, weight: .bold, mono: true, align: .right)
                c.text("free", x: r.maxX - 9, y: 3, size: Metrics.Font.caption, color: theme.dim, align: .right)
            }
        }
    }
}
