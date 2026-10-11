import AppKit

/// Headless renderer: `widefive --snapshot <mode> out.png [seconds]` renders a mode at native Touch Bar resolution (2170×60).
public enum Snapshot {
    public static func render(mode: String, seconds: Double = 1.5, width: CGFloat = 1085, scale: CGFloat = 2,
                              script: ((StripController, Double) -> Void)? = nil) -> Data? {
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
        let dt = 1.0 / 60
        var t = 0.0
        while t < seconds {
            script?(controller, t)
            controller.step(dt: dt)
            controller.current.update(dt: dt)
            t += dt
            if Int(t * 60) % 60 == 0 { Stats.shared.sample() }
        }
        gc.cgContext.clear(CGRect(origin: .zero, size: size))
        controller.render(gc.cgContext, size: size)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
