import AppKit

/// Owns the active mode, routes input (Touch Bar touches, preview-window mouse/keys) and drives the render loop.
public final class StripController {
    public let registry: ModeRegistry
    public let ctx = ModeContext()
    public let gestures = GestureEngine()
    public let actions = ActionRunner()
    public private(set) var current: StripMode
    public var onModeChange: ((StripMode) -> Void)?
    public var onConfigNeedsPresent: (() -> Void)?

    private var views: [NSView] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastRefresh: Double = 0
    private var history: [String] = []
    private var toastText: String?
    private var toastUntil: Double = 0
    private var hud: (icon: String, value: Float, until: Double)?
    private var exitTouch: Int?
    private var claimed: Set<Int> = []
    private let startTime = CACurrentMediaTime()

    public static let exitWidth: CGFloat = 24
    /// Exit + key-lock buttons shown on the left of every game.
    public static let gameChromeWidth: CGFloat = 50
    public private(set) var paused = false
    /// Asked to toggle the keyboard lock (the app owns the event tap).
    public var onToggleKeyLock: (() -> Void)?
    private var lockTouch: Int?

    public init(registry: ModeRegistry = .standard(), config: Config = .default) {
        self.registry = registry
        current = registry.mode(config.startMode) ?? registry.modes[0]
        apply(config: config)
        actions.switchMode = { [weak self] id in self?.switchTo(id) }
        actions.toast = { [weak self] s in self?.toast(s) }
        ctx.requestRedraw = { [weak self] in self?.setNeedsDisplay() }
        ctx.switchMode = { [weak self] id in self?.switchTo(id) }
        ctx.goBack = { [weak self] in self?.goBack() }
        ctx.toast = { [weak self] s in self?.toast(s) }
        ctx.run = { [weak self] a in self?.actions.run(a) }
        gestures.emit = { [weak self] out in self?.handleGesture(out) }
        current.activate(ctx)
    }

    public func apply(config: Config) {
        ctx.config = config
        ctx.theme = Theme.named(config.theme)
        gestures.config = config.gestures
        Weather.shared.location = config.weatherLocation
        setNeedsDisplay()
    }

    // MARK: Views & loop

    public func attach(_ view: NSView) {
        views.append(view)
        startLoop()
    }

    public func detach(_ view: NSView) { views.removeAll { $0 === view } }

    public func startLoop() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 20.0, now - lastTick)
        lastTick = now
        Stats.shared.sampleIfNeeded()
        if paused {
            if now - lastRefresh > 0.5 { lastRefresh = now; setNeedsDisplay() }
        } else if current.isAnimated {
            current.update(dt: dt)
            setNeedsDisplay()
        } else if now - lastRefresh >= current.refreshInterval {
            lastRefresh = now
            current.update(dt: dt)
            setNeedsDisplay()
        } else if toastText != nil || hud != nil {
            setNeedsDisplay()
        }
    }

    public func setNeedsDisplay() { views.forEach { $0.needsDisplay = true } }

    // MARK: Modes

    public func switchTo(_ id: String) {
        guard let next = registry.mode(id), next !== current else { return }
        if current.id != "launcher" { history.append(current.id) }
        if history.count > 20 { history.removeFirst() }
        activate(next)
    }

    public func goBack() {
        let id = history.popLast() ?? "home"
        if let m = registry.mode(id) { activate(m) }
    }

    public func togglePause() {
        guard current.isGame else { return }
        paused.toggle()
        toast(paused ? "⏸ paused — P or tap to resume" : "▶︎ resumed")
    }

    private func activate(_ m: StripMode) {
        current.deactivate()
        paused = false
        lockTouch = nil
        if !m.isGame, KeyCapture.shared.active { KeyCapture.shared.stop() }
        claimed.removeAll()
        exitTouch = nil
        current = m
        m.activate(ctx)
        lastRefresh = 0
        onModeChange?(m)
        setNeedsDisplay()
    }

    public func frontmostChanged(bundleId: String?, name: String?) {
        ctx.frontmostBundleId = bundleId
        ctx.frontmostAppName = name
        if let layout = ctx.config.layout(for: bundleId), let m = layout.mode { switchTo(m) }
        (current as? HomeMode)?.rebuild()
        setNeedsDisplay()
    }

    public func toast(_ s: String) {
        toastText = s
        toastUntil = CACurrentMediaTime() + 2.5
        setNeedsDisplay()
    }

    private func handleGesture(_ g: GestureEngine.Output) {
        switch g {
        case .volume(let v):
            SystemControl.volume = v
            hud = ("speaker.wave.2.fill", v, CACurrentMediaTime() + 1.2)
        case .brightness(let v):
            SystemControl.brightness = v
            hud = ("sun.max.fill", v, CACurrentMediaTime() + 1.2)
        case .playPause:
            SystemControl.media("playpause")
            toast("⏯")
        case .launcher:
            switchTo("launcher")
        case .flick(let dir):
            let order = ctx.config.flickOrder.filter { registry.mode($0) != nil }
            guard !order.isEmpty else { return }
            let i = order.firstIndex(of: current.id) ?? -1
            switchTo(order[(i + dir + order.count) % order.count])
        }
        setNeedsDisplay()
    }

    // MARK: Input

    public func touchBegan(_ t: StripTouch) {
        if current.showsExitButton, t.x < Self.exitWidth { exitTouch = t.id; return }
        if current.isGame, t.x < Self.gameChromeWidth { lockTouch = t.id; return }
        if paused { paused = false; setNeedsDisplay(); return }
        if current.allowsGestures, gestures.began(t) {
            // Cancel any in-flight mode touches: the gesture owns the group now.
            for id in claimed { current.touchCancelled(StripTouch(id: id, x: t.x, y: t.y, startX: t.x, startTime: t.time, time: t.time)) }
            claimed.removeAll()
            return
        }
        claimed.insert(t.id)
        current.touchBegan(t)
        setNeedsDisplay()
    }

    public func touchMoved(_ t: StripTouch) {
        if exitTouch == t.id || lockTouch == t.id { return }
        if current.allowsGestures, gestures.moved(t) { return }
        if claimed.contains(t.id) { current.touchMoved(t) }
        setNeedsDisplay()
    }

    public func touchEnded(_ t: StripTouch) {
        if exitTouch == t.id {
            exitTouch = nil
            if t.x < Self.exitWidth + 10 { goBack() }
            return
        }
        if lockTouch == t.id {
            lockTouch = nil
            if t.x < Self.gameChromeWidth + 10 { onToggleKeyLock?() }
            setNeedsDisplay()
            return
        }
        let consumedByGesture = current.allowsGestures && gestures.ended(t)
        if claimed.remove(t.id) != nil {
            if consumedByGesture { current.touchCancelled(t) } else { current.touchEnded(t) }
        }
        setNeedsDisplay()
    }

    public func keyDown(_ k: GameKey) {
        if paused { paused = false; return }
        current.keyDown(k)
    }
    public func keyUp(_ k: GameKey) { current.keyUp(k) }

    // MARK: Render

    public func render(_ cg: CGContext, size: CGSize) {
        ctx.size = size
        let now = CACurrentMediaTime()
        let c = Canvas(cg: cg, size: size, theme: ctx.theme, time: now - startTime)
        c.clear(ctx.theme.background)
        current.draw(c)
        if current.showsExitButton {
            let r = CGRect(x: 0, y: 0, width: Self.exitWidth - 2, height: size.height)
            c.roundRect(r, radius: 6, fill: NSColor(white: exitTouch == nil ? 0.12 : 0.3, alpha: 0.92))
            c.symbol("xmark", in: r, color: .white, pointSize: 11)
        }
        if current.isGame {
            let locked = KeyCapture.shared.active
            let r = CGRect(x: Self.exitWidth, y: 0, width: Self.gameChromeWidth - Self.exitWidth - 2, height: size.height)
            c.roundRect(r, radius: 6, fill: locked ? ctx.theme.accent : NSColor(white: lockTouch == nil ? 0.12 : 0.3, alpha: 0.92))
            c.symbol(locked ? "keyboard.fill" : "keyboard", in: r, color: locked ? .black : .white, pointSize: 11)
        }
        if paused {
            c.fill(c.bounds, NSColor(white: 0, alpha: 0.55))
            c.text("PAUSED · P or tap to resume", x: size.width / 2, size: 12, color: .white, weight: .heavy, align: .center)
        }
        if let h = hud {
            if now > h.until { hud = nil } else { drawHUD(c, h.icon, h.value) }
        }
        if let s = toastText {
            if now > toastUntil { toastText = nil } else { drawToast(c, s, fade: min(1, (toastUntil - now) / 0.4)) }
        }
    }

    private func drawHUD(_ c: Canvas, _ icon: String, _ v: Float) {
        let w: CGFloat = 320
        let r = CGRect(x: (c.width - w) / 2, y: 2, width: w, height: c.height - 4)
        c.roundRect(r, radius: 8, fill: NSColor(white: 0.08, alpha: 0.95), stroke: c.theme.accent2, lineWidth: 1)
        c.symbol(icon, in: CGRect(x: r.minX + 6, y: r.minY, width: 24, height: r.height), color: .white, pointSize: 12)
        let track = CGRect(x: r.minX + 36, y: r.midY - 3, width: w - 80, height: 6)
        c.roundRect(track, radius: 3, fill: NSColor(white: 0.25, alpha: 1))
        c.gradient(CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(v), height: 6), [c.theme.accent, c.theme.accent2], horizontal: true, radius: 3)
        c.text("\(Int(v * 100))", x: r.maxX - 8, size: 11, color: .white, weight: .semibold, mono: true, align: .right)
    }

    private func drawToast(_ c: Canvas, _ s: String, fade: Double) {
        let maxW = min(c.width - 80, 700)
        let w = min(maxW, Canvas.measure(s, size: 12) + 28)
        let r = CGRect(x: (c.width - w) / 2, y: 2, width: w, height: c.height - 4)
        c.cg.setAlpha(CGFloat(fade))
        c.roundRect(r, radius: 8, fill: NSColor(white: 0.1, alpha: 0.96), stroke: c.theme.accent, lineWidth: 1)
        c.text(s, x: r.midX, size: 12, color: .white, align: .center, maxWidth: w - 20)
        c.cg.setAlpha(1)
    }
}
