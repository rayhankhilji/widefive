import AppKit

/// Control bar: the stuff the stock Control Strip gives you, laid out properly and with the extras
/// (keyboard backlight, dark mode, caffeine, screenshot, Mission Control) you actually reach for.
public final class ControlMode: StripMode {
    public let id = "control"
    public let title = "Controls"
    public let icon = "slider.horizontal.3"
    public var refreshInterval: Double { 0.5 }
    public var isAnimated: Bool { dragging != nil || presses.animating || anim.values.contains { !$0.settled } }
    public var allowsGestures: Bool { false }
    public var showsExitButton: Bool { true }

    private enum Kind { case slider(String), button(String, String) }
    private struct Cell { var kind: Kind; var frame: CGRect = .zero; var width: CGFloat; var group: Int }

    private var ctx: ModeContext?
    private var cells: [Cell] = []
    private var pressed: Int?
    private var dragging: Int?
    private var caffeinate: Process?
    private let presses = Presses<Int>()
    private var anim: [String: Smoothed] = [:]

    public init() { build() }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    private func build() {
        cells = [
            Cell(kind: .slider("volume"), width: 164, group: 0),
            Cell(kind: .button("mute", "speaker.slash.fill"), width: 42, group: 0),
            Cell(kind: .slider("brightness"), width: 164, group: 1),
            Cell(kind: .slider("keyboard"), width: 164, group: 1),
            Cell(kind: .button("prev", "backward.fill"), width: 42, group: 2),
            Cell(kind: .button("playpause", "playpause.fill"), width: 50, group: 2),
            Cell(kind: .button("next", "forward.fill"), width: 42, group: 2),
            Cell(kind: .button("dark", "circle.lefthalf.filled"), width: 42, group: 3),
            Cell(kind: .button("caffeine", "cup.and.saucer.fill"), width: 42, group: 3),
            Cell(kind: .button("shot", "camera.viewfinder"), width: 42, group: 3),
            Cell(kind: .button("mission", "rectangle.3.group"), width: 42, group: 3),
            Cell(kind: .button("lock", "lock.fill"), width: 42, group: 3),
            Cell(kind: .button("sleep", "moon.zzz.fill"), width: 42, group: 3),
        ]
    }

    private func layout(_ width: CGFloat) {
        let x0 = Metrics.contentX
        let gap = Metrics.gap, groupGap = Metrics.groupGap
        let groups = CGFloat(Set(cells.map(\.group)).count - 1)
        let fixed = gap * (CGFloat(cells.count - 1) - groups) + groupGap * groups
        let natural = cells.reduce(0) { $0 + $1.width }
        let scale = min(1, (width - x0 - 2 - fixed) / natural)
        // Spread any spare room into the group gaps so the bar always spans edge to edge.
        let spare = max(0, width - x0 - 2 - fixed - natural * scale)
        let extra = groups > 0 ? min(spare / groups, 28) : 0
        var x = x0
        for i in cells.indices {
            if i > 0 { x += cells[i].group != cells[i - 1].group ? groupGap + extra : gap }
            let w = cells[i].width * scale
            cells[i].frame = CGRect(x: x, y: 1.5, width: w, height: 27)
            x += w
        }
    }

    private func value(_ name: String) -> Float {
        switch name {
        case "brightness": return SystemControl.brightness
        case "keyboard": return KeyboardLight.brightness
        default: return SystemControl.volume
        }
    }

    private func setValue(_ name: String, _ v: Float) {
        let v = max(0, min(1, v))
        switch name {
        case "brightness": SystemControl.brightness = v
        case "keyboard": KeyboardLight.brightness = v
        default: SystemControl.volume = v
        }
    }

    private func icon(_ name: String) -> String {
        switch name {
        case "brightness": return "sun.max.fill"
        case "keyboard": return "keyboard"
        default: return SystemControl.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
    }

    public func draw(_ c: Canvas) {
        layout(c.width)
        let theme = c.theme
        for (i, cell) in cells.enumerated() {
            let r = cell.frame
            let p = presses.amount(i)
            switch cell.kind {
            case .slider(let name):
                let target = Double(value(name))
                if anim[name] == nil { anim[name] = Smoothed(target, speed: 26) }
                anim[name]?.target = target
                let v = CGFloat(max(0, min(1, anim[name]?.value ?? target)))
                let active = dragging == i
                c.panel(r, fill: active ? theme.surface.mix(theme.surfaceHi, 0.6) : theme.surface)
                c.symbol(icon(name), in: CGRect(x: r.minX + 4, y: r.minY, width: 22, height: r.height), color: theme.accent, pointSize: Metrics.iconSmall + 0.5)
                let track = CGRect(x: r.minX + 30, y: r.midY - 2.5, width: r.width - 62, height: 5)
                c.meter(track, value: v)
                let knob = CGPoint(x: track.minX + track.width * v, y: track.midY)
                let kr: CGFloat = active ? 7 : 5.5
                c.glowing(theme.accent, blur: active ? 9 : 5, strength: active ? 1 : 0.5) {
                    c.circle(center: knob, radius: kr, theme.isLight ? .white : theme.text)
                }
                if theme.isLight { c.roundRect(CGRect(x: knob.x - kr, y: knob.y - kr, width: kr * 2, height: kr * 2), radius: kr, fill: .clear, stroke: NSColor(white: 0, alpha: 0.18), lineWidth: 0.5) }
                c.text("\(Int((v * 100).rounded()))", x: r.maxX - 8, size: Metrics.Font.label - 0.5, color: active ? theme.text : theme.dim,
                       weight: .semibold, mono: true, align: .right)
            case .button(let name, let sym):
                let on = isOn(name)
                c.button(r, style: on ? .filled(nil) : .plain, pressed: p) { fg in
                    c.symbol(sym, in: r, color: fg, pointSize: Metrics.icon)
                }
            }
        }
    }

    private func isOn(_ name: String) -> Bool {
        switch name {
        case "mute": return SystemControl.isMuted
        case "caffeine": return caffeinate != nil
        default: return false
        }
    }

    private func hit(_ x: CGFloat) -> Int? { cells.firstIndex { $0.frame.minX <= x && x <= $0.frame.maxX } }

    public func update(dt: Double) {
        presses.step(dt)
        for k in anim.keys { anim[k]?.step(dt) }
    }

    public func touchBegan(_ t: StripTouch) {
        guard let i = hit(t.x) else { return }
        switch cells[i].kind {
        case .slider(let name):
            dragging = i
            setValue(name, slide(cells[i].frame, t.x))
        case .button:
            pressed = i
            presses.press(i)
        }
    }

    public func touchMoved(_ t: StripTouch) {
        guard let i = dragging, case .slider(let name) = cells[i].kind else { return }
        setValue(name, slide(cells[i].frame, t.x))
    }

    private func slide(_ r: CGRect, _ x: CGFloat) -> Float {
        Float((x - (r.minX + 30)) / max(1, r.width - 62))
    }

    public func touchEnded(_ t: StripTouch) {
        if let p = pressed { presses.release(p) }
        defer { pressed = nil; dragging = nil }
        guard dragging == nil, let i = pressed, hit(t.x) == i, case .button(let name, _) = cells[i].kind else { return }
        run(name)
    }

    private func run(_ name: String) {
        guard let ctx else { return }
        switch name {
        case "mute": SystemControl.setMuted(!SystemControl.isMuted)
        case "prev", "next", "playpause": SystemControl.media(name)
        case "dark":
            ctx.run(Action(applescript: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"))
        case "caffeine":
            if let p = caffeinate { p.terminate(); caffeinate = nil; ctx.toast("caffeine off") }
            else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                p.arguments = ["-dimsu"]
                try? p.run()
                caffeinate = p
                ctx.toast("caffeine on — Mac stays awake")
            }
        case "shot": Keys.sendChord("cmd+shift+4")
        case "mission": Keys.sendChord("ctrl+up")
        case "lock": Keys.sendChord("ctrl+cmd+q")
        case "sleep": ctx.run(Action(shell: "pmset displaysleepnow"))
        default: break
        }
        ctx.requestRedraw()
    }

    public func touchCancelled(_ t: StripTouch) { pressed = nil; dragging = nil; presses.cancelAll() }
    public func deactivate() { pressed = nil; dragging = nil }
}
