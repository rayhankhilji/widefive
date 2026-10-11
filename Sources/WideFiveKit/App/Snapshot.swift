import AppKit

/// Headless renderer: `widefive --snapshot <mode> out.png [seconds]` renders a mode at native Touch Bar resolution (2170×60).
public enum Snapshot {
    /// Writes a PNG sequence (frame-0000.png …) for GIFs/videos: `widefive --frames <mode> <dir> <seconds> [width] [fps] [skip]`.
    @discardableResult
    public static func frames(mode: String, dir: String, seconds: Double, width: CGFloat = 1085, fps: Double = 30,
                              skip: Double = 0, scale: CGFloat = 2) -> Int {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var n = 0
        var next = skip
        _ = render(mode: mode, seconds: skip + seconds, width: width, scale: scale, frame: { t, png in
            guard t >= next else { return }
            next += 1 / fps
            try? png().write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "frame-%04d.png", n)))
            n += 1
        })
        return n
    }

    /// Average CPU time per rendered frame: `widefive --bench <mode> [seconds] [width]`.
    public static func bench(mode: String, seconds: Double, width: CGFloat) -> (ms: Double, worst: Double) {
        var total = 0.0, worst = 0.0, n = 0
        var draw: (() -> Void)?
        _ = render(mode: mode, seconds: seconds, width: width, frame: { _, _ in
            let t0 = CACurrentMediaTime(); draw?(); let e = CACurrentMediaTime() - t0
            total += e; worst = max(worst, e); n += 1
        }, rawDraw: { draw = $0 })
        return (total / Double(max(1, n)) * 1000, worst * 1000)
    }

    public static func render(mode: String, seconds: Double = 1.5, width: CGFloat = 1085, scale: CGFloat = 2,
                              script: ((StripController, Double) -> Void)? = nil,
                              frame: ((Double, () -> Data) -> Void)? = nil, rawDraw: ((@escaping () -> Void) -> Void)? = nil) -> Data? {
        let themed = mode.split(separator: "@", maxSplits: 1).map(String.init)
        let parts = themed[0].split(separator: ":").map(String.init)
        let modeId = parts[0]
        let demo = parts.count > 1 && parts[1] == "demo"
        var cfg = Config.default
        cfg.startMode = modeId
        if themed.count > 1 { cfg.theme = themed[1] }
        let controller = StripController(config: cfg)
        controller.frontmostChanged(bundleId: "com.microsoft.VSCode", name: "Code")
        controller.switchTo(modeId)
        Stats.shared.sample()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(30 * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        gc.cgContext.scaleBy(x: scale, y: scale)
        let size = CGSize(width: width, height: 30)
        // One throwaway frame so modes learn the real strip width before the demo starts.
        controller.render(gc.cgContext, size: size)
        if demo { (controller.current as? DemoStartable)?.startDemo() }
        rawDraw? { gc.cgContext.clear(CGRect(origin: .zero, size: size)); controller.render(gc.cgContext, size: size) }
        let dt = 1.0 / 60
        var t = 0.0
        while t < seconds {
            script?(controller, t)
            controller.step(dt: dt)
            controller.current.update(dt: dt)
            t += dt
            if Int(t * 60) % 60 == 0 { Stats.shared.sample() }
            if let frame {
                frame(t) {
                    gc.cgContext.clear(CGRect(origin: .zero, size: size))
                    controller.render(gc.cgContext, size: size)
                    return rep.representation(using: .png, properties: [:]) ?? Data()
                }
            }
        }
        gc.cgContext.clear(CGRect(origin: .zero, size: size))
        controller.render(gc.cgContext, size: size)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
