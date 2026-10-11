// Draws widefive's artwork with CoreGraphics so it stays reproducible from source.
//   swift Scripts/art.swift icon <out.png> [size]        app icon (default 1024)
//   swift Scripts/art.swift dmg  <out.png> [scale]       DMG window background, 660x420 pt
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func save(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Apple's continuous-corner "squircle" approximated with a superellipse.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, c = CGPoint(x: r.midX, y: r.midY)
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let ct = cos(t), st = sin(t)
        let x = c.x + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = c.y + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let neon: [UInt32] = [0xff2d95, 0xff7a3d, 0xffd23f, 0x3dffb4, 0x37b6ff]

/// The Touch Bar strip with five neon segments; `r` is the strip's outer rect.
func drawStrip(_ ctx: CGContext, _ r: CGRect, glow: CGFloat) {
    let radius = r.height / 2
    let body = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // soft colored bloom under the strip
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: glow * 2.2, color: rgb(0xb04dff, 0.55))
    ctx.addPath(body); ctx.setFillColor(rgb(0x05050c)); ctx.fillPath()
    ctx.restoreGState()

    // glass body
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    linear(ctx, [rgb(0x1a1a28), rgb(0x050509), rgb(0x0b0b14)], [0, 0.55, 1],
           from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))

    // segments
    let pad = r.height * 0.16, gap = r.height * 0.11
    let inner = r.insetBy(dx: pad * 1.2, dy: pad)
    let weights: [CGFloat] = [1.0, 1.55, 0.8, 1.25, 1.0]
    let unit = (inner.width - gap * CGFloat(weights.count - 1)) / weights.reduce(0, +)
    var x = inner.minX
    for (i, w) in weights.enumerated() {
        let seg = CGRect(x: x, y: inner.minY, width: unit * w, height: inner.height)
        let sr = seg.height * 0.32
        let path = CGPath(roundedRect: seg, cornerWidth: sr, cornerHeight: sr, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: glow, color: rgb(neon[i], 0.95))
        ctx.addPath(path); ctx.setFillColor(rgb(neon[i])); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        linear(ctx, [rgb(0xffffff, 0.55), rgb(0xffffff, 0.0), rgb(0x000000, 0.18)], [0, 0.5, 1],
               from: CGPoint(x: 0, y: seg.maxY), to: CGPoint(x: 0, y: seg.minY))
        ctx.restoreGState()
        x += seg.width + gap
    }
    // glossy top highlight
    let gloss = CGRect(x: r.minX + radius * 0.6, y: r.midY + r.height * 0.18, width: r.width - radius * 1.2, height: r.height * 0.26)
    ctx.addPath(CGPath(roundedRect: gloss, cornerWidth: gloss.height / 2, cornerHeight: gloss.height / 2, transform: nil))
    ctx.setFillColor(rgb(0xffffff, 0.07)); ctx.fillPath()
    ctx.restoreGState()

    // rim
    ctx.addPath(body)
    ctx.setLineWidth(max(1, r.height * 0.035))
    ctx.setStrokeColor(rgb(0xffffff, 0.16)); ctx.strokePath()
}

func drawIcon(size: Int) -> CGContext {
    let s = CGFloat(size)
    let ctx = bitmap(size, size)
    let tile = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let shape = squircle(tile)

    // drop shadow (Big Sur grid: content 824/1024, shadow below)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0x000000, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x0b0820)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    linear(ctx, [rgb(0x2a1660), rgb(0x120c34), rgb(0x07061a)], [0, 0.5, 1],
           from: CGPoint(x: tile.minX, y: tile.maxY), to: CGPoint(x: tile.maxX, y: tile.minY))
    radial(ctx, [rgb(0xff2d95, 0.35), rgb(0xff2d95, 0)], center: CGPoint(x: tile.minX + tile.width * 0.15, y: tile.maxY - tile.height * 0.1), radius: tile.width * 0.75)
    radial(ctx, [rgb(0x37b6ff, 0.28), rgb(0x37b6ff, 0)], center: CGPoint(x: tile.maxX - tile.width * 0.05, y: tile.minY + tile.height * 0.12), radius: tile.width * 0.7)

    // perspective floor grid below the strip
    let horizon = tile.minY + tile.height * 0.42
    ctx.saveGState()
    ctx.clip(to: CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: horizon - tile.minY))
    ctx.setLineWidth(max(1, s * 0.0028))
    let vanish = CGPoint(x: tile.midX, y: horizon + tile.height * 0.08)
    for i in -12...12 {
        let bx = tile.midX + CGFloat(i) * tile.width * 0.11
        ctx.move(to: vanish); ctx.addLine(to: CGPoint(x: bx, y: tile.minY))
    }
    for i in 1...9 {
        let t = pow(CGFloat(i) / 9, 1.9)
        let y = horizon - (horizon - tile.minY) * t
        ctx.move(to: CGPoint(x: tile.minX, y: y)); ctx.addLine(to: CGPoint(x: tile.maxX, y: y))
    }
    ctx.replacePathWithStrokedPath(); ctx.clip()
    linear(ctx, [rgb(0xb04dff, 0.0), rgb(0xb04dff, 0.55)], [0, 1], from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: tile.minY))
    ctx.restoreGState()

    // stars
    var seed: UInt64 = 0x5eed
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<40 {
        let p = CGPoint(x: tile.minX + rnd() * tile.width, y: horizon + tile.height * 0.12 + rnd() * tile.height * 0.45)
        let r = s * (0.0018 + rnd() * 0.003)
        ctx.setFillColor(rgb(0xffffff, 0.25 + rnd() * 0.5))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    // inner top sheen
    linear(ctx, [rgb(0xffffff, 0.10), rgb(0xffffff, 0)], [0, 1], from: CGPoint(x: 0, y: tile.maxY), to: CGPoint(x: 0, y: tile.maxY - tile.height * 0.25))
    ctx.restoreGState()

    // the strip, wider than the tile, like the bar spanning the keyboard
    let strip = CGRect(x: tile.minX + tile.width * 0.07, y: tile.minY + tile.height * 0.445, width: tile.width * 0.86, height: tile.height * 0.155)
    drawStrip(ctx, strip, glow: s * 0.03)

    // tile edge
    ctx.addPath(shape); ctx.setLineWidth(max(1, s * 0.003)); ctx.setStrokeColor(rgb(0xffffff, 0.12)); ctx.strokePath()
    return ctx
}

func text(_ ctx: CGContext, _ str: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor, kern: CGFloat = 0) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    let a = NSAttributedString(string: str, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color)!, .kern: kern,
    ])
    let w = a.size().width
    a.draw(at: CGPoint(x: p.x - w / 2, y: p.y))
    NSGraphicsContext.restoreGraphicsState()
}

func drawDMG(scale: CGFloat) -> CGContext {
    let W: CGFloat = 660, H: CGFloat = 420
    let ctx = bitmap(Int(W * scale), Int(H * scale))
    ctx.scaleBy(x: scale, y: scale)
    linear(ctx, [rgb(0x1d1150), rgb(0x0d0a26), rgb(0x06050f)], [0, 0.55, 1], from: CGPoint(x: 0, y: H), to: CGPoint(x: W, y: 0))
    radial(ctx, [rgb(0xff2d95, 0.22), rgb(0xff2d95, 0)], center: CGPoint(x: 60, y: H - 20), radius: 420)
    radial(ctx, [rgb(0x37b6ff, 0.18), rgb(0x37b6ff, 0)], center: CGPoint(x: W - 40, y: 40), radius: 380)

    // thin Touch Bar strip as the header ornament
    drawStrip(ctx, CGRect(x: W / 2 - 150, y: H - 70, width: 300, height: 24), glow: 9)
    text(ctx, "widefive", at: CGPoint(x: W / 2, y: H - 118), size: 30, weight: .heavy, color: rgb(0xffffff), kern: -0.5)
    text(ctx, "your Touch Bar, taken over", at: CGPoint(x: W / 2, y: H - 140), size: 12.5, weight: .medium, color: rgb(0xffffff, 0.55), kern: 0.4)

    // icon wells: Finder centres the icons at y = 222 from the top (198 from the bottom), labels below
    for x in [CGFloat(170), 490] {
        let well = CGRect(x: x - 78, y: 104, width: 156, height: 174)
        let path = CGPath(roundedRect: well, cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        linear(ctx, [rgb(0xffffff, 0.07), rgb(0xffffff, 0.025)], [0, 1], from: CGPoint(x: 0, y: well.maxY), to: CGPoint(x: 0, y: well.minY))
        // light plate behind Finder's label so it reads in both light (black text) and dark (white text) mode
        let plate = CGRect(x: well.minX + 14, y: 114, width: well.width - 28, height: 24)
        ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(rgb(0xb9b2e6, 0.62)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.setLineWidth(1); ctx.setStrokeColor(rgb(0xffffff, 0.10)); ctx.strokePath()
    }

    // arrow: dotted neon trail into a glowing chevron
    let y: CGFloat = 200, x0: CGFloat = 268, x1: CGFloat = 392
    for i in 0..<9 {
        let t = CGFloat(i) / 8
        let px = x0 + (x1 - 26 - x0) * t
        let r = 2.2 + 1.4 * t
        let c = t < 0.5 ? neon[Int(t * 4)] : neon[min(4, Int(t * 4) + 1)]
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6, color: rgb(c, 0.8))
        ctx.setFillColor(rgb(c, 0.55 + 0.45 * t))
        ctx.fillEllipse(in: CGRect(x: px - r, y: y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.setLineWidth(4.5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: x1 - 15, y: y + 15)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.addLine(to: CGPoint(x: x1 - 15, y: y - 15))
    ctx.setShadow(offset: .zero, blur: 10, color: rgb(neon[4], 0.95))
    ctx.setStrokeColor(rgb(neon[4])); ctx.strokePath()
    ctx.restoreGState()
    text(ctx, "DRAG TO INSTALL", at: CGPoint(x: 330, y: 220), size: 9.5, weight: .bold, color: rgb(0xffffff, 0.45), kern: 1.6)

    // footer: first-launch hint for ad-hoc signed builds
    let foot = CGRect(x: 40, y: 26, width: W - 80, height: 46)
    ctx.addPath(CGPath(roundedRect: foot, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(rgb(0x000000, 0.28)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: foot, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setLineWidth(1); ctx.setStrokeColor(rgb(0xffffff, 0.08)); ctx.strokePath()
    text(ctx, "FIRST LAUNCH", at: CGPoint(x: W / 2, y: 52), size: 8.5, weight: .bold, color: rgb(neon[3], 0.85), kern: 1.4)
    text(ctx, "Right-click widefive → Open, or System Settings → Privacy & Security → Open Anyway",
         at: CGPoint(x: W / 2, y: 34), size: 11, weight: .medium, color: rgb(0xffffff, 0.7))
    return ctx
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: art.swift icon|dmg out.png [size|scale]"); exit(2) }
switch args[1] {
case "icon": save(drawIcon(size: args.count > 3 ? Int(args[3])! : 1024), args[2])
case "dmg": save(drawDMG(scale: args.count > 3 ? CGFloat(Double(args[3])!) : 1), args[2])
default: print("unknown artwork \(args[1])"); exit(2)
}
