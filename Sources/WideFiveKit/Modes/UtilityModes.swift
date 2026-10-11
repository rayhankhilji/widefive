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
    private var scroll: CGFloat = 0, scrollStart: CGFloat = 0, scrolling = false
    private var longFired = false
    private var work: DispatchWorkItem?
    private var ctx: ModeContext?
    private static let shared = ClipboardWatcher.shared

    public init() { ClipboardWatcher.shared.start() }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    public func draw(_ c: Canvas) {
        history = ClipboardWatcher.shared.items
        let x0 = StripController.exitWidth + 4
        frames = []
        if history.isEmpty {
            c.text("Copy something — it’ll show up here (passwords from managers are ignored).", x: x0 + 8, size: 12, color: c.theme.dim)
            return
        }
        var x = x0 - scroll
        c.clip(CGRect(x: x0, y: 0, width: c.width - x0, height: 30)) {
            for (i, s) in history.enumerated() {
                let label = s.replacingOccurrences(of: "\n", with: " ⏎ ").trimmingCharacters(in: .whitespaces)
                let w = min(220, Canvas.measure(label, size: 11) + 26)
                let r = CGRect(x: x, y: 0, width: w, height: 30)
                frames.append(r)
                c.roundRect(r, radius: 6, fill: pressed == i ? c.theme.buttonPressed : c.theme.button)
                c.text("\(i + 1)", x: r.minX + 6, y: 18, size: 7, color: c.theme.accent, weight: .bold)
                c.text(label, x: r.minX + 14, size: 11, color: c.theme.text, maxWidth: w - 20)
                x += w + 5
            }
        }
    }

    private func hit(_ x: CGFloat) -> Int? { frames.firstIndex { $0.minX <= x && x <= $0.maxX } }

    public func touchBegan(_ t: StripTouch) {
        pressed = hit(t.x); scrollStart = scroll; scrolling = false; longFired = false
        work?.cancel()
        guard let i = pressed else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.pressed == i, !self.scrolling else { return }
            self.longFired = true
            ClipboardWatcher.shared.copy(self.history[i])
            Keys.sendChord("cmd+v")
            self.ctx?.toast("pasted")
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    public func touchMoved(_ t: StripTouch) {
        if abs(t.dx) > 8 {
            scrolling = true; pressed = nil
            let total = (frames.last?.maxX ?? 0) + scroll - (StripController.exitWidth + 4)
            scroll = max(0, min(max(0, total - 900), scrollStart - t.dx))
        }
    }

    public func touchEnded(_ t: StripTouch) {
        work?.cancel()
        defer { pressed = nil }
        guard let i = pressed, !scrolling, !longFired, i < history.count else { return }
        ClipboardWatcher.shared.copy(history[i])
        ctx?.toast("copied: \(history[i].prefix(40))")
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

    public init() {}

    public func update(dt: Double) {
        apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    public func activate(_ ctx: ModeContext) { update(dt: 0) }

    public func draw(_ c: Canvas) {
        let x0 = StripController.exitWidth + 6
        let w: CGFloat = 40
        frames = []
        let front = NSWorkspace.shared.frontmostApplication
        for (i, app) in apps.enumerated() {
            let r = CGRect(x: x0 + CGFloat(i) * (w + 4), y: 0, width: w, height: 30)
            guard r.maxX < c.width else { break }
            frames.append(r)
            if pressed == i || app == front { c.roundRect(r, radius: 6, fill: pressed == i ? c.theme.buttonPressed : c.theme.button) }
            if let icon = app.icon { c.image(icon, in: CGRect(x: r.midX - 12, y: 3, width: 24, height: 24)) }
            if app.isHidden { c.fill(CGRect(x: r.midX - 4, y: 0.5, width: 8, height: 1), c.theme.dim) }
            else { c.circle(center: CGPoint(x: r.midX, y: 1.5), radius: 1, c.theme.accent2) }
        }
    }

    private func hit(_ x: CGFloat) -> Int? { frames.firstIndex { $0.minX <= x && x <= $0.maxX } }

    public func touchBegan(_ t: StripTouch) {
        pressed = hit(t.x); longFired = false
        work?.cancel()
        guard let i = pressed, i < apps.count else { return }
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
        let x0 = StripController.exitWidth + 4
        let avail = c.width - x0
        let sections: [(String, CGFloat)] = [("cpu", 0.3), ("ram", 0.14), ("net", 0.22), ("temp", 0.12), ("bat", 0.11), ("disk", 0.11)]
        var x = x0
        for (name, frac) in sections {
            let r = CGRect(x: x, y: 0, width: avail * frac - 5, height: 30)
            x += avail * frac
            c.roundRect(r, radius: 6, fill: c.theme.button)
            switch name {
            case "cpu":
                c.clip(r) { sparkline(c, s.cpuHistory, in: r.insetBy(dx: 2, dy: 2), color: meterColor(c, s.cpu), maxValue: 1) }
                c.text("CPU", x: r.minX + 8, y: 16, size: 9, color: c.theme.dim, weight: .bold)
                c.text("\(Int(s.cpu * 100))%", x: r.maxX - 8, size: 16, color: c.theme.text, weight: .bold, mono: true, align: .right)
            case "ram":
                let f = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
                c.fill(CGRect(x: r.minX + 6, y: 4, width: (r.width - 12) * CGFloat(f), height: 3), meterColor(c, f))
                c.text("RAM", x: r.minX + 8, y: 16, size: 9, color: c.theme.dim, weight: .bold)
                c.text("\(Stats.bytes(s.memUsed))/\(Stats.bytes(s.memTotal))", x: r.maxX - 6, y: 9, size: 10, color: c.theme.text, mono: true, align: .right)
            case "net":
                c.clip(r) { sparkline(c, s.netHistory, in: r.insetBy(dx: 2, dy: 2), color: c.theme.accent2) }
                c.text("↓ " + Stats.bytes(s.netDown, perSec: true), x: r.minX + 8, y: 15, size: 11, color: c.theme.text, mono: true)
                c.text("↑ " + Stats.bytes(s.netUp, perSec: true), x: r.minX + 8, y: 3, size: 11, color: c.theme.dim, mono: true)
            case "temp":
                let t = s.temperature.map { "\(Int($0))°C" } ?? "—"
                let f = s.fan.map { "\(Int($0)) rpm" } ?? ""
                c.text(t, x: r.midX, y: 13, size: 13, color: c.theme.text, weight: .bold, mono: true, align: .center)
                c.text(f, x: r.midX, y: 2, size: 9, color: c.theme.dim, mono: true, align: .center)
            case "bat":
                c.text(s.battery.map { "\(Int($0 * 100))%" } ?? "AC", x: r.midX, y: 13, size: 13, color: c.theme.text, weight: .bold, mono: true, align: .center)
                c.text(s.charging ? "charging" : "battery", x: r.midX, y: 2, size: 9, color: c.theme.dim, align: .center)
            default:
                c.text(Stats.bytes(s.diskFree), x: r.midX, y: 13, size: 13, color: c.theme.text, weight: .bold, mono: true, align: .center)
                c.text("free", x: r.midX, y: 2, size: 9, color: c.theme.dim, align: .center)
            }
        }
    }
}
