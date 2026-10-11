import AppKit

/// Control bar: the stuff the stock Control Strip gives you, laid out properly and with the extras
/// (keyboard backlight, dark mode, caffeine, screenshot, Mission Control) you actually reach for.
public final class ControlMode: StripMode {
    public let id = "control"
    public let title = "Controls"
    public let icon = "slider.horizontal.3"
    public var refreshInterval: Double { 0.5 }
    public var allowsGestures: Bool { false }
    public var showsExitButton: Bool { true }

    private enum Kind { case slider(String), button(String, String) }
    private struct Cell { var kind: Kind; var frame: CGRect = .zero; var width: CGFloat }

    private var ctx: ModeContext?
    private var cells: [Cell] = []
    private var pressed: Int?
    private var dragging: Int?
    private var caffeinate: Process?

    public init() { build() }

    public func activate(_ ctx: ModeContext) { self.ctx = ctx }

    private func build() {
        cells = [
            Cell(kind: .slider("volume"), width: 186),
            Cell(kind: .button("mute", "speaker.slash.fill"), width: 44),
            Cell(kind: .slider("brightness"), width: 186),
            Cell(kind: .slider("keyboard"), width: 186),
            Cell(kind: .button("prev", "backward.fill"), width: 44),
            Cell(kind: .button("playpause", "playpause.fill"), width: 52),
            Cell(kind: .button("next", "forward.fill"), width: 44),
            Cell(kind: .button("dark", "circle.lefthalf.filled"), width: 44),
            Cell(kind: .button("caffeine", "cup.and.saucer.fill"), width: 44),
            Cell(kind: .button("shot", "camera.viewfinder"), width: 44),
            Cell(kind: .button("mission", "rectangle.3.group"), width: 44),
            Cell(kind: .button("lock", "lock.fill"), width: 44),
            Cell(kind: .button("sleep", "moon.zzz.fill"), width: 44),
        ]
    }

    private func layout(_ width: CGFloat) {
        let x0 = StripController.exitWidth + 4
        let gap: CGFloat = 4
        let natural = cells.reduce(0) { $0 + $1.width } + gap * CGFloat(cells.count - 1)
        let scale = min(1, (width - x0 - 4) / natural)
        var x = x0
        for i in cells.indices {
            let w = cells[i].width * scale
            cells[i].frame = CGRect(x: x, y: 1, width: w, height: 28)
            x += w + gap
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
        for (i, cell) in cells.enumerated() {
            let r = cell.frame
            switch cell.kind {
            case .slider(let name):
                c.roundRect(r, radius: 7, fill: c.theme.button)
                c.symbol(icon(name), in: CGRect(x: r.minX + 3, y: r.minY, width: 22, height: r.height), color: c.theme.text, pointSize: 12)
                let track = CGRect(x: r.minX + 28, y: r.midY - 2.5, width: r.width - 38, height: 5)
                let v = CGFloat(value(name))
                c.roundRect(track, radius: 2.5, fill: c.theme.dim.withAlphaComponent(0.35))
                c.gradient(CGRect(x: track.minX, y: track.minY, width: max(5, track.width * v), height: 5), [c.theme.accent, c.theme.accent2], horizontal: true, radius: 2.5)
                c.circle(center: CGPoint(x: track.minX + track.width * v, y: track.midY), radius: dragging == i ? 7 : 5.5, .white)
            case .button(let name, let sym):
                let on = isOn(name)
                let base = on ? c.theme.accent : c.theme.button
                c.roundRect(r, radius: 7, fill: pressed == i ? (base.blended(withFraction: 0.35, of: .white) ?? base) : base)
                c.symbol(sym, in: r, color: on ? .black : c.theme.text, pointSize: 13)
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

    public func touchBegan(_ t: StripTouch) {
        guard let i = hit(t.x) else { return }
        switch cells[i].kind {
        case .slider(let name):
            dragging = i
            setValue(name, slide(cells[i].frame, t.x))
        case .button:
            pressed = i
        }
    }

    public func touchMoved(_ t: StripTouch) {
        guard let i = dragging, case .slider(let name) = cells[i].kind else { return }
        setValue(name, slide(cells[i].frame, t.x))
    }

    private func slide(_ r: CGRect, _ x: CGFloat) -> Float {
        Float((x - (r.minX + 28)) / max(1, r.width - 38))
    }

    public func touchEnded(_ t: StripTouch) {
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

    public func deactivate() { pressed = nil; dragging = nil }
}
