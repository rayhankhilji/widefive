import AppKit

/// A small live tile inside the Home layout.
public protocol Widget: AnyObject {
    func width(_ ctx: ModeContext) -> CGFloat
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext)
    func tap(_ ctx: ModeContext)
    /// Tap with the strip x position (widgets with several targets inside); defaults to `tap(_:)`.
    func tap(_ ctx: ModeContext, at x: CGFloat)
    func longPress(_ ctx: ModeContext)
    func swipe(_ dx: CGFloat, ctx: ModeContext)
    /// True while the widget wants 60 fps (pulsing, scrolling); the home bar otherwise redraws twice a second.
    var animating: Bool { get }
}

public extension Widget {
    func tap(_ ctx: ModeContext) {}
    func tap(_ ctx: ModeContext, at x: CGFloat) { tap(ctx) }
    func longPress(_ ctx: ModeContext) {}
    func swipe(_ dx: CGFloat, ctx: ModeContext) {}
    var animating: Bool { false }
}

public enum WidgetFactory {
    public static let names = ["clock", "date", "cpu", "ram", "battery", "net", "temp", "fan", "nowplaying", "weather", "pomodoro", "disk", "uptime", "app", "agents"]

    public static func make(_ name: String, width: CGFloat? = nil) -> Widget? {
        switch name.lowercased() {
        case "clock": return ClockWidget(showSeconds: false)
        case "clock.seconds": return ClockWidget(showSeconds: true)
        case "date": return DateWidget()
        case "cpu": return CPUWidget()
        case "ram", "memory": return RAMWidget()
        case "battery": return BatteryWidget()
        case "net", "network": return NetWidget()
        case "temp", "temperature": return TempWidget()
        case "fan": return FanWidget()
        case "nowplaying", "music": return NowPlayingWidget(width: width ?? 170)
        case "weather": return WeatherWidget()
        case "pomodoro": return PomodoroWidget.shared
        case "disk": return DiskWidget()
        case "uptime": return UptimeWidget()
        case "app": return FrontAppWidget()
        case "agents", "agent": return AgentsWidget()
        default: return nil
        }
    }
}

// MARK: - Helpers

func tile(_ c: Canvas, _ r: CGRect, pressed: Bool) {
    c.panel(r, fill: pressed ? c.theme.surfaceHi : c.theme.surface)
}

func sparkline(_ c: Canvas, _ values: [Double], in r: CGRect, color: NSColor, maxValue: Double? = nil) {
    guard values.count > 1 else { return }
    let m = max(maxValue ?? (values.max() ?? 1), 0.0001)
    let step = r.width / CGFloat(values.count - 1)
    let path = CGMutablePath()
    for (i, v) in values.enumerated() {
        let p = CGPoint(x: r.minX + CGFloat(i) * step, y: r.minY + 1 + CGFloat(min(v / m, 1)) * (r.height - 2))
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    let stroke = path.copy()!
    path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    path.addLine(to: CGPoint(x: r.minX, y: r.minY))
    path.closeSubpath()
    c.cg.saveGState()
    c.cg.addPath(path)
    c.cg.clip()
    c.gradient(r, [color.withAlphaComponent(0.32), color.withAlphaComponent(0.02)])
    c.cg.restoreGState()
    c.cg.saveGState()
    c.cg.addPath(stroke)
    c.cg.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
    c.cg.setLineWidth(1)
    c.cg.setLineJoin(.round)
    c.cg.strokePath()
    c.cg.restoreGState()
}

func meterColor(_ c: Canvas, _ v: Double) -> NSColor { v < 0.5 ? c.theme.good : v < 0.8 ? c.theme.warn : c.theme.bad }

// MARK: - Widgets

final class ClockWidget: Widget {
    let showSeconds: Bool
    init(showSeconds: Bool) { self.showSeconds = showSeconds }
    private lazy var fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        return f
    }()
    func width(_ ctx: ModeContext) -> CGFloat { showSeconds ? 70 : 52 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        c.text(fmt.string(from: Date()), x: r.midX, size: Metrics.Font.title - 0.5, color: c.theme.text, weight: .semibold, mono: true, align: .center)
    }
    func tap(_ ctx: ModeContext) { ctx.run(Action(open: "com.apple.iCal")) }
}

final class DateWidget: Widget {
    private let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
    func width(_ ctx: ModeContext) -> CGFloat { 84 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        c.text(fmt.string(from: Date()), x: r.midX, size: Metrics.Font.label + 0.5, color: c.theme.text, weight: .medium, align: .center)
    }
}

final class CPUWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 78 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let s = Stats.shared
        c.clip(r) { sparkline(c, s.cpuHistory.suffix(30).map { $0 }, in: r.insetBy(dx: 2, dy: 2), color: meterColor(c, s.cpu), maxValue: 1) }
        c.caption("CPU", x: r.minX + 7)
        c.text("\(Int(s.cpu * 100))%", x: r.maxX - 7, size: Metrics.Font.body, color: c.theme.text, weight: .semibold, mono: true, align: .right)
    }
    func tap(_ ctx: ModeContext) { ctx.switchMode("stats") }
}

final class RAMWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 82 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let s = Stats.shared
        let frac = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
        c.meter(CGRect(x: r.minX + 7, y: r.minY + 4, width: r.width - 14, height: 2.5), value: CGFloat(frac), colors: [meterColor(c, frac).withAlphaComponent(0.7), meterColor(c, frac)])
        c.caption("RAM", x: r.minX + 7)
        c.text(Stats.bytes(s.memUsed), x: r.maxX - 7, size: Metrics.Font.label + 0.5, color: c.theme.text, weight: .semibold, mono: true, align: .right)
    }
    func tap(_ ctx: ModeContext) { ctx.switchMode("stats") }
}

final class BatteryWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 64 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let s = Stats.shared
        guard let b = s.battery else {
            c.symbol("powerplug.fill", in: r, color: c.theme.dim, pointSize: 12); return
        }
        let body = CGRect(x: r.minX + 6, y: r.midY - 5, width: 20, height: 10)
        c.roundRect(body, radius: 3, fill: .clear, stroke: c.theme.dim.withAlphaComponent(0.8), lineWidth: 1)
        c.fill(CGRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4), c.theme.dim)
        let col = s.charging ? c.theme.good : (b < 0.2 ? c.theme.bad : c.theme.text)
        c.roundRect(CGRect(x: body.minX + 1.5, y: body.minY + 1.5, width: max(1, (body.width - 3) * CGFloat(b)), height: body.height - 3), radius: 1.5, fill: col)
        c.text("\(Int(b * 100))", x: r.maxX - 6, size: 12, color: c.theme.text, weight: .semibold, mono: true, align: .right)
        if s.charging { c.symbol("bolt.fill", in: body, color: c.theme.on(col), pointSize: 7) }
    }
}

final class NetWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 88 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let s = Stats.shared
        c.clip(r) { sparkline(c, s.netHistory.suffix(30).map { $0 }, in: r.insetBy(dx: 2, dy: 2), color: c.theme.accent2) }
        c.text("↓" + Stats.bytes(s.netDown, perSec: true), x: r.minX + 5, y: r.midY - 1, size: 9, color: c.theme.text, mono: true)
        c.text("↑" + Stats.bytes(s.netUp, perSec: true), x: r.minX + 5, y: r.minY + 1, size: 9, color: c.theme.dim, mono: true)
    }
}

final class TempWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { Stats.shared.temperature == nil ? 0 : 58 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        guard let t = Stats.shared.temperature else { return }
        tile(c, r, pressed: pressed)
        let col = t < 60 ? c.theme.good : t < 85 ? c.theme.warn : c.theme.bad
        c.symbol("thermometer.medium", in: CGRect(x: r.minX + 2, y: r.minY, width: 16, height: r.height), color: col, pointSize: 11)
        c.text("\(Int(t))°", x: r.maxX - 6, size: 12, color: c.theme.text, weight: .semibold, mono: true, align: .right)
    }
    func tap(_ ctx: ModeContext) { ctx.switchMode("stats") }
}

final class FanWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { Stats.shared.fan == nil ? 0 : 74 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        guard let f = Stats.shared.fan else { return }
        tile(c, r, pressed: pressed)
        let icon = CGRect(x: r.minX + 3, y: r.minY, width: 18, height: r.height)
        c.cg.saveGState()
        c.cg.translateBy(x: icon.midX, y: icon.midY)
        c.cg.rotate(by: CGFloat(c.time * f / 400))
        c.cg.translateBy(x: -icon.midX, y: -icon.midY)
        c.symbol("fanblades.fill", in: icon, color: c.theme.accent2, pointSize: 11)
        c.cg.restoreGState()
        c.text("\(Int(f))", x: r.maxX - 6, size: 11, color: c.theme.text, mono: true, align: .right)
    }
}

final class DiskWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 76 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        c.symbol("internaldrive", in: CGRect(x: r.minX + 2, y: r.minY, width: 20, height: r.height), color: c.theme.dim, pointSize: 11)
        c.text(Stats.bytes(Stats.shared.diskFree), x: r.maxX - 6, size: 12, color: c.theme.text, mono: true, align: .right)
    }
}

final class UptimeWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { 70 }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let u = Int(Stats.shared.uptime)
        let s = u > 86400 ? "\(u / 86400)d \(u % 86400 / 3600)h" : "\(u / 3600)h \(u % 3600 / 60)m"
        c.symbol("clock", in: CGRect(x: r.minX + 3, y: r.minY, width: 18, height: r.height), color: c.theme.dim, pointSize: 10)
        c.text(s, x: r.maxX - 7, size: Metrics.Font.label, color: c.theme.text, weight: .medium, mono: true, align: .right)
    }
}

final class WeatherWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat { Weather.shared.summary.isEmpty ? 40 : max(60, Canvas.measure(Weather.shared.summary, size: 12) + 14) }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        Weather.shared.refreshIfNeeded()
        tile(c, r, pressed: pressed)
        let s = Weather.shared.summary
        c.text(s.isEmpty ? "☁︎ …" : s, x: r.midX, size: Metrics.Font.label + 0.5, color: c.theme.text, weight: .medium, align: .center)
    }
    func tap(_ ctx: ModeContext) { ctx.run(Action(url: "https://wttr.in/\(ctx.config.weatherLocation)")) }
}

final class FrontAppWidget: Widget {
    func width(_ ctx: ModeContext) -> CGFloat {
        let name = ctx.config.layout(for: ctx.frontmostBundleId)?.name ?? ctx.frontmostAppName ?? "Desktop"
        return min(130, Canvas.measure(name, size: 11, weight: .semibold) + 34)
    }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        let name = ctx.config.layout(for: ctx.frontmostBundleId)?.name ?? ctx.frontmostAppName ?? "Desktop"
        if let bid = ctx.frontmostBundleId, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first, let icon = app.icon {
            c.image(icon, in: CGRect(x: r.minX + 2, y: r.midY - 11, width: 22, height: 22))
        }
        c.text(name, x: r.minX + 28, size: 11, color: c.theme.dim, weight: .semibold, maxWidth: r.width - 30)
    }
}

final class NowPlayingWidget: Widget {
    let w: CGFloat
    init(width: CGFloat) { w = width; NowPlaying.shared.start() }
    func width(_ ctx: ModeContext) -> CGFloat { NowPlaying.shared.title.isEmpty ? 0 : w }
    func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        let np = NowPlaying.shared
        guard !np.title.isEmpty else { return }
        tile(c, r, pressed: pressed)
        var x = r.minX + 3
        if let art = np.artwork {
            c.image(art, in: CGRect(x: x, y: r.minY + 3, width: r.height - 6, height: r.height - 6), radius: 3)
            x += r.height - 3
        } else {
            c.symbol(np.isPlaying ? "music.note" : "pause.fill", in: CGRect(x: x, y: r.minY, width: 20, height: r.height), color: c.theme.accent, pointSize: 11)
            x += 22
        }
        let textW = r.maxX - x - 4
        let line = np.artist.isEmpty ? np.title : "\(np.title) — \(np.artist)"
        let full = Canvas.measure(line, size: 11, weight: .semibold)
        c.clip(CGRect(x: x, y: r.minY, width: textW, height: r.height)) {
            if full > textW, np.isPlaying {
                let loop = full + 40
                let off = CGFloat((c.time * 28).truncatingRemainder(dividingBy: Double(loop)))
                c.text(line, x: x - off, y: r.midY - 2, size: 11, color: c.theme.text, weight: .semibold)
                c.text(line, x: x - off + loop, y: r.midY - 2, size: 11, color: c.theme.text, weight: .semibold)
            } else {
                c.text(line, x: x, y: r.midY - 2, size: 11, color: c.theme.text, weight: .semibold, maxWidth: textW)
            }
        }
        if np.duration > 0 {
            let p = CGFloat(min(1, np.position / np.duration))
            c.meter(CGRect(x: x, y: r.minY + 4, width: textW, height: 2), value: p)
        }
    }
    func tap(_ ctx: ModeContext) { SystemControl.media("playpause") }
    func swipe(_ dx: CGFloat, ctx: ModeContext) { SystemControl.media(dx < 0 ? "next" : "prev") }
}

public final class PomodoroWidget: Widget {
    public static let shared = PomodoroWidget()
    private var endAt: Date?
    private var remainingWhenPaused: TimeInterval?
    private var breakMode = false

    func total(_ ctx: ModeContext) -> TimeInterval { breakMode ? 5 * 60 : ctx.config.pomodoroMinutes * 60 }
    func remaining(_ ctx: ModeContext) -> TimeInterval {
        if let endAt { return max(0, endAt.timeIntervalSinceNow) }
        return remainingWhenPaused ?? total(ctx)
    }

    public func width(_ ctx: ModeContext) -> CGFloat { 80 }
    public func draw(_ c: Canvas, in r: CGRect, pressed: Bool, ctx: ModeContext) {
        tile(c, r, pressed: pressed)
        let rem = remaining(ctx)
        if endAt != nil, rem <= 0 {
            endAt = nil; remainingWhenPaused = nil
            ctx.toast(breakMode ? "☕️ Break over — back to work" : "🍅 Pomodoro done — take 5")
            NSSound(named: "Glass")?.play()
            breakMode.toggle()
        }
        let frac = 1 - rem / total(ctx)
        let center = CGPoint(x: r.minX + 14, y: r.midY)
        let col = breakMode ? c.theme.good : c.theme.bad
        c.glowing(col, blur: 5, strength: endAt == nil ? 0 : 0.8) {
            c.ring(center: center, radius: 7.5, width: 2.5, fraction: CGFloat(frac), color: col)
        }
        if endAt == nil { c.symbol("play.fill", in: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12), color: c.theme.dim, pointSize: 6) }
        let m = Int(rem) / 60, s = Int(rem) % 60
        c.text(String(format: "%d:%02d", m, s), x: r.maxX - 6, size: 12, color: endAt == nil ? c.theme.dim : c.theme.text, weight: .semibold, mono: true, align: .right)
    }
    public func tap(_ ctx: ModeContext) {
        if let endAt { remainingWhenPaused = endAt.timeIntervalSinceNow; self.endAt = nil }
        else { endAt = Date().addingTimeInterval(remaining(ctx)); remainingWhenPaused = nil }
    }
    public func longPress(_ ctx: ModeContext) { endAt = nil; remainingWhenPaused = nil; breakMode = false; ctx.toast("🍅 reset") }
}
