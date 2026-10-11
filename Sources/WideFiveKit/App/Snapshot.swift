import AppKit

/// Headless renderer: `widefive --snapshot <mode> out.png [seconds]` renders a mode at native Touch Bar resolution (2170×60).
public enum Snapshot {
    public static func render(mode: String, seconds: Double = 1.5, width: CGFloat = 1085, scale: CGFloat = 2,
                              script: ((StripController, Double) -> Void)? = nil) -> Data? {
        var cfg = Config.default
        cfg.startMode = mode
        let controller = StripController(config: cfg)
        controller.frontmostChanged(bundleId: "com.microsoft.VSCode", name: "Code")
        controller.switchTo(mode)
        Stats.shared.sample()
        let dt = 1.0 / 60
        var t = 0.0
        while t < seconds {
            script?(controller, t)
            controller.current.update(dt: dt)
            t += dt
            if Int(t * 60) % 60 == 0 { Stats.shared.sample() }
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(30 * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        gc.cgContext.scaleBy(x: scale, y: scale)
        controller.render(gc.cgContext, size: CGSize(width: width, height: 30))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
