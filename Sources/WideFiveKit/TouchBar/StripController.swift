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
    private var hud: (kind: String, until: Double, start: Double)?
    private var hudValue = Smoothed(0, speed: 22)
    private var exitTouch: Int?
    private var claimed: Set<Int> = []
    private let startTime = CACurrentMediaTime()

    // Motion state (driven by `step(dt:)`, so headless snapshots animate deterministically).
    private var clock: Double = 0
    private var toastText: String?
    private var toastStart: Double = 0
    private var toastUntil: Double = 0
    private var toastWidth = Smoothed(0, speed: 20)
    private var pauseAmount = Smoothed(0, speed: 16)
    private let chrome = Presses<String>()
    private struct Transition {
        enum Kind { case slide(CGFloat), fade }
        var kind: Kind
        var from: StripMode?
        var fromTheme: Theme
        var image: CGImage?
        var start: Double
        var duration: Double
    }
    private var transition: Transition?
    private var started = false
    private var lastScale: CGFloat = 2

    public static let exitWidth: CGFloat = 24
    /// Exit + key-lock buttons shown on the left of every game.
    public static let gameChromeWidth: CGFloat = 50
    public private(set) var paused = false
    /// Asked to toggle the keyboard lock (the app owns the event tap).
    public var onToggleKeyLock: (() -> Void)?
    /// Asked to persist a theme picked on the bar (the app owns the config file).
    public var onThemePicked: ((String) -> Void)?
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
        (registry.mode("themes") as? ThemesMode)?.pick = { [weak self] name in
            self?.previewTheme(name)
            self?.onThemePicked?(name)
        }
        current.activate(ctx)
        started = true
    }

    public func apply(config: Config) {
        let old = ctx.theme
        let next = Theme.named(config.theme)
        if started, old.name != next.name { beginTransition(.fade, theme: old, duration: 0.45) }
        ctx.config = config
        ctx.theme = next
        gestures.config = config.gestures
        Weather.shared.location = config.weatherLocation
        AgentMonitor.shared.config = config.agents
        setNeedsDisplay()
    }

    /// Live theme preview (used by the Themes mode): crossfades immediately, no config round-trip needed.
    public func previewTheme(_ name: String) {
        var cfg = ctx.config
        cfg.theme = Theme.named(name).name
        apply(config: cfg)
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
        step(dt: dt)
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
        }
        if motionActive { setNeedsDisplay() }
    }

    /// Advances controller-level motion (transitions, toasts, HUD, pause, chrome presses).
    public func step(dt: Double) {
        clock += dt
        chrome.step(dt)
        pauseAmount.target = paused ? 1 : 0
        pauseAmount.step(dt)
        hudValue.step(dt)
        toastWidth.step(dt)
        if let tr = transition, clock - tr.start >= tr.duration { transition = nil; setNeedsDisplay() }
        if let h = hud, clock > h.until { hud = nil; setNeedsDisplay() }
        if toastText != nil, clock > toastUntil { toastText = nil; setNeedsDisplay() }
    }

    private var motionActive: Bool {
        transition != nil || toastText != nil || hud != nil || !pauseAmount.settled || chrome.animating
    }

    public func setNeedsDisplay() { views.forEach { $0.needsDisplay = true } }

    // MARK: Modes

    public func switchTo(_ id: String) {
        guard let next = registry.mode(id), next !== current else { return }
        if current.id != "launcher" { history.append(current.id) }
        if history.count > 20 { history.removeFirst() }
        activate(next, direction: 1)
    }

    public func goBack() {
        let id = history.popLast() ?? "home"
        if let m = registry.mode(id) { activate(m, direction: -1) }
    }

    public func togglePause() {
        guard current.isGame else { return }
        paused.toggle()
        setNeedsDisplay()
    }

    private func activate(_ m: StripMode, direction: CGFloat) {
        if started { beginTransition(.slide(direction), theme: ctx.theme, duration: 0.42) }
        current.deactivate()
        paused = false
        pauseAmount.snap(0)
        lockTouch = nil
        if !m.isGame, KeyCapture.shared.active { KeyCapture.shared.stop() }
        claimed.removeAll()
        exitTouch = nil
        chrome.cancelAll()
        current = m
        m.activate(ctx)
        lastRefresh = 0
        onModeChange?(m)
        setNeedsDisplay()
    }

    /// Freezes the outgoing frame into an image so the incoming mode can slide/crossfade over it.
    private func beginTransition(_ kind: Transition.Kind, theme: Theme, duration: Double) {
        guard ctx.size.width > 1 else { return }
        let image = captureFrame(theme: theme)
        transition = Transition(kind: kind, from: nil, fromTheme: theme, image: image, start: clock, duration: duration)
    }

    private func captureFrame(theme: Theme) -> CGImage? {
        let size = ctx.size
        let s = lastScale
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: Int(size.width * s), height: Int(size.height * s), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.scaleBy(x: s, y: s)
        let c = Canvas(cg: cg, size: size, theme: theme, time: CACurrentMediaTime() - startTime)
        if let img = transition?.image, transition.map({ clock - $0.start < $0.duration }) == true {
            // Mid-transition: freeze what is actually on screen.
            drawTransition(c, img)
        } else {
            drawContent(c)
        }
        return cg.makeImage()
    }

    public func frontmostChanged(bundleId: String?, name: String?) {
        ctx.frontmostBundleId = bundleId
        ctx.frontmostAppName = name
        if let layout = ctx.config.layout(for: bundleId), let m = layout.mode { switchTo(m) }
        (current as? HomeMode)?.rebuild()
        setNeedsDisplay()
    }

    public func toast(_ s: String) {
        if toastText == nil || clock > toastUntil - 0.3 { toastStart = clock }
        if toastText == nil { toastWidth.snap(Double(toastTargetWidth(s))) }
        toastText = s
        toastUntil = clock + 2.4
        setNeedsDisplay()
    }

    private func showHUD(_ kind: String, _ v: Float) {
        if hud == nil || clock > (hud?.until ?? 0) - 0.25 {
            hudValue.snap(Double(v))
            hud = (kind, clock + 1.4, clock)
        } else if let h = hud {
            hud = (kind, clock + 1.4, h.start)
        }
        hudValue.target = Double(v)
    }

    private func handleGesture(_ g: GestureEngine.Output) {
        switch g {
        case .volume(let v):
            SystemControl.volume = v
            showHUD("volume", v)
        case .brightness(let v):
            SystemControl.brightness = v
            showHUD("brightness", v)
        case .playPause:
            SystemControl.media("playpause")
            toast("⏯  Play / Pause")
        case .launcher:
            switchTo("launcher")
        case .flick(let dir):
            let order = ctx.config.flickOrder.filter { registry.mode($0) != nil }
            guard !order.isEmpty else { return }
            let i = order.firstIndex(of: current.id) ?? -1
            if let m = registry.mode(order[(i + dir + order.count) % order.count]), m !== current {
                if current.id != "launcher" { history.append(current.id) }
                activate(m, direction: CGFloat(dir >= 0 ? 1 : -1))
            }
        }
        setNeedsDisplay()
    }

    // MARK: Input

    public func touchBegan(_ t: StripTouch) {
        if current.showsExitButton, t.x < Self.exitWidth { exitTouch = t.id; chrome.press("exit"); setNeedsDisplay(); return }
        if current.isGame, t.x < Self.gameChromeWidth { lockTouch = t.id; chrome.press("lock"); setNeedsDisplay(); return }
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
            chrome.release("exit")
            if t.x < Self.exitWidth + 10 { goBack() }
            return
        }
        if lockTouch == t.id {
            lockTouch = nil
            chrome.release("lock")
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
        if paused { paused = false; setNeedsDisplay(); return }
        current.keyDown(current.isTwoPlayer ? k : k.collapsed)
    }
    public func keyUp(_ k: GameKey) { current.keyUp(current.isTwoPlayer ? k : k.collapsed) }

    // MARK: Render

    public func render(_ cg: CGContext, size: CGSize) {
        ctx.size = size
        lastScale = max(1, min(4, abs(cg.userSpaceToDeviceSpaceTransform.a)))
        let c = Canvas(cg: cg, size: size, theme: ctx.theme, time: CACurrentMediaTime() - startTime)
        if let img = transition?.image { drawTransition(c, img) } else { drawContent(c) }
        drawPause(c)
        if let h = hud { drawHUD(c, h) }
        if let s = toastText { drawToast(c, s) }
    }

    private func drawTransition(_ c: Canvas, _ img: CGImage) {
        guard let tr = transition else { drawContent(c); return }
        let e = CGFloat(Ease.outQuint((clock - tr.start) / tr.duration))
        c.clear(c.theme.background)
        switch tr.kind {
        case .slide(let dir):
            let d: CGFloat = 56
            c.faded(max(0, 1 - e * 1.5)) { c.translated(-dir * d * e) { c.cg.draw(img, in: c.bounds) } }
            c.faded(min(1, e * 1.2)) { c.translated(dir * d * (1 - e)) { drawContent(c) } }
        case .fade:
            drawContent(c)
            c.faded(1 - e) { c.cg.draw(img, in: c.bounds) }
        }
    }

    /// Background, mode and game chrome — everything a transition moves as one piece.
    private func drawContent(_ c: Canvas) {
        c.background()
        current.draw(c)
        let h = c.height
        if current.showsExitButton {
            let r = CGRect(x: 1, y: 1.5, width: Self.exitWidth - 3, height: h - 3)
            c.button(r, style: .plain, pressed: chrome.amount("exit")) { fg in
                c.symbol("xmark", in: r, color: fg.withAlphaComponent(0.9), pointSize: 9.5)
            }
        }
        if current.isGame {
            let locked = KeyCapture.shared.active
            let r = CGRect(x: Self.exitWidth, y: 1.5, width: Self.gameChromeWidth - Self.exitWidth - 3, height: h - 3)
            c.button(r, style: locked ? .filled(nil) : .plain, pressed: chrome.amount("lock")) { fg in
                c.symbol(locked ? "keyboard.fill" : "keyboard", in: r, color: fg, pointSize: 10)
            }
        }
    }

    private func drawPause(_ c: Canvas) {
        let a = pauseAmount.cg
        guard a > 0.004 else { return }
        let x0 = current.isGame ? Self.gameChromeWidth : 0
        let area = CGRect(x: x0, y: 0, width: c.width - x0, height: c.height)
        c.fill(area, c.theme.background.withAlphaComponent(0.66 * a))
        let w: CGFloat = 272
        let r = CGRect(x: area.midX - w / 2, y: 3, width: w, height: c.height - 6)
        let theme = c.theme
        c.faded(a) {
            c.translated(0, -5 * (1 - a)) {
                c.glowing(theme.accent, blur: 12, strength: 0.5) { c.panel(r, fill: theme.surfaceHi, radius: r.height / 2) }
                let dot = CGPoint(x: r.minX + 14, y: r.midY)
                c.glowing(theme.accent, blur: 6, strength: 0.8) { c.circle(center: dot, radius: 8, theme.accent) }
                c.symbol("pause.fill", in: CGRect(x: dot.x - 8, y: dot.y - 8, width: 16, height: 16), color: theme.onAccent, pointSize: 7.5)
                c.text("Paused", x: r.minX + 28, size: Metrics.Font.body, color: theme.text, weight: .bold)
                c.caption("P or tap to resume", x: r.maxX - 14, align: .right)
            }
        }
    }

    private func drawHUD(_ c: Canvas, _ h: (kind: String, until: Double, start: Double)) {
        let theme = c.theme
        let (dy, alpha, scale) = popIn(age: clock - h.start, left: h.until - clock, height: c.height)
        let v = CGFloat(max(0, min(1, hudValue.value)))
        let icon: String
        if h.kind == "volume" {
            icon = v < 0.01 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        } else {
            icon = v < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
        let w: CGFloat = 340
        let r = CGRect(x: (c.width - w) / 2, y: 3, width: w, height: c.height - 6)
        c.translated(0, dy) { c.faded(alpha) { c.scaled(scale, around: CGPoint(x: r.midX, y: r.midY)) {
            c.glowing(theme.accent2, blur: 12, strength: 0.6) { c.panel(r, fill: theme.surfaceHi, radius: r.height / 2) }
            c.symbol(icon, in: CGRect(x: r.minX + 8, y: r.minY, width: 22, height: r.height), color: theme.accent, pointSize: 11)
            let track = CGRect(x: r.minX + 38, y: r.midY - 2.5, width: w - 38 - 50, height: 5)
            c.meter(track, value: v)
            let knob = CGPoint(x: track.minX + track.width * v, y: track.midY)
            c.glowing(theme.accent, blur: 6, strength: 0.9) { c.circle(center: knob, radius: 5, theme.isLight ? .white : theme.text) }
            c.text("\(Int((v * 100).rounded()))%", x: r.maxX - 12, size: Metrics.Font.label, color: theme.text, weight: .semibold, mono: true, align: .right)
        } } }
    }

    /// Shared spring-up entrance / sink-away exit for floating pills.
    private func popIn(age: Double, left: Double, height: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let inP = CGFloat(Ease.outBack(age / 0.42, 1.25))
        let outP = CGFloat(Ease.inOutCubic(1 - left / 0.3))
        let dy = -(1 - inP) * height * 0.9 - outP * height * 0.7
        let alpha = CGFloat(Ease.clamp(age / 0.14)) * (1 - outP)
        let scale = 0.92 + 0.08 * min(1.05, inP) - 0.05 * outP
        return (dy, alpha, scale)
    }

    private func toastTargetWidth(_ s: String) -> CGFloat {
        min(ctx.size.width - 120, 680, Canvas.measure(s, size: Metrics.Font.body, weight: .semibold) + 46)
    }

    private func drawToast(_ c: Canvas, _ s: String) {
        let theme = c.theme
        toastWidth.target = Double(toastTargetWidth(s))
        let (dy, alpha, scale) = popIn(age: clock - toastStart, left: toastUntil - clock, height: c.height)
        let w = toastWidth.cg
        let r = CGRect(x: (c.width - w) / 2, y: 3, width: w, height: c.height - 6)
        let rad = r.height / 2
        let remaining = CGFloat(Ease.clamp((toastUntil - clock) / 2.4))
        c.translated(0, dy) { c.faded(alpha) { c.scaled(scale, around: CGPoint(x: r.midX, y: r.midY)) {
            c.glowing(theme.accent, blur: 12, strength: 0.55) { c.panel(r, fill: theme.surfaceHi, radius: rad) }
            let dot = CGPoint(x: r.minX + 13, y: r.midY)
            c.glowing(theme.accent, blur: 5, strength: 1) { c.circle(center: dot, radius: 2.5, theme.accent) }
            c.clip(r.insetBy(dx: 10, dy: 0)) {
                c.text(s, x: r.midX + 5, size: Metrics.Font.body, color: theme.text, weight: .semibold, align: .center, maxWidth: w - 40)
            }
            c.fill(CGRect(x: r.minX + rad, y: r.minY + 1.5, width: (r.width - rad * 2) * remaining, height: 1), theme.accent.withAlphaComponent(0.45))
        } } }
    }
}
