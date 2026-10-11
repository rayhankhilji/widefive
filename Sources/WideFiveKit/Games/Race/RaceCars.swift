import AppKit

struct CarPose {
    var steer: CGFloat = 0
    var brake = false
    var boost = false
    var wheel: CGFloat = 0       // tread scroll phase
    var wing: CGFloat = 0        // active aero 0…1
    var time: Double = 0
    var night = false
    var sheen: CGFloat?          // garage reflection sweep, -1…1
    var seed = 0
}

/// Rear-view car art, drawn as vectors in a unit space (width 1, ground at y 0) at three levels of detail.
enum CarArt {
    static func draw(_ c: Canvas, _ car: RaceCar, paint: RCol? = nil, cx: CGFloat, by: CGFloat, w: CGFloat, pose: CarPose = CarPose()) {
        guard w > 1.2 else { return }
        let cg = c.cg
        let pen = Pen(cg: cg)
        let col = paint ?? car.color
        cg.saveGState()
        cg.translateBy(x: cx, y: by)
        cg.scaleBy(x: w, y: w)
        if w < 7 {
            tiny(pen, car, col, pose)
            cg.restoreGState()
            return
        }
        let p = Painter(pen: pen, col: col, pose: pose, detail: w >= 17, px: 1 / w)
        p.shadow(car.aspect)
        p.tyres(car.model)
        cg.saveGState()
        cg.translateBy(x: pose.steer * 0.012, y: 0.06)
        cg.rotate(by: -pose.steer * 0.045)
        cg.translateBy(x: 0, y: -0.06)
        switch car.model {
        case .lambo: p.lambo()
        case .f1: p.f1()
        case .defender: p.defender()
        case .gwagon: p.gwagon()
        case .m5: p.m5()
        case .r8: p.r8()
        case .laferrari: p.laferrari()
        }
        if pose.boost { for e in exhausts(car.model) { p.flame(e.x, e.y) } }
        cg.restoreGState()
        cg.restoreGState()
    }

    static func exhausts(_ m: RaceCar.Model) -> [CGPoint] {
        switch m {
        case .lambo: return [CGPoint(x: 0, y: 0.115)]
        case .f1: return [CGPoint(x: 0, y: 0.185)]
        case .defender: return [CGPoint(x: 0.3, y: 0.085)]
        case .gwagon: return [CGPoint(x: -0.255, y: 0.105), CGPoint(x: 0.255, y: 0.105)]
        case .m5: return [CGPoint(x: -0.24, y: 0.1), CGPoint(x: 0.24, y: 0.1)]
        case .r8: return [CGPoint(x: -0.3, y: 0.155), CGPoint(x: 0.3, y: 0.155)]
        case .laferrari: return [CGPoint(x: 0, y: 0.18)]
        }
    }

    /// Far-away cars: a handful of blocks that still read as the right shape and colour.
    private static func tiny(_ p: Pen, _ car: RaceCar, _ col: RCol, _ pose: CarPose) {
        let h = car.aspect
        p.rect(-0.46, 0, 0.22, h * 0.3, RCol(0x101012)); p.rect(0.24, 0, 0.22, h * 0.3, RCol(0x101012))
        switch car.model {
        case .f1:
            p.rect(-0.14, 0.05, 0.28, 0.28, col); p.rect(-0.27, 0.37, 0.54, 0.08, col.dark(0.3))
        case .defender, .gwagon:
            p.rect(-0.47, 0.12, 0.94, h * 0.62, col); p.rect(-0.38, h * 0.66, 0.76, h * 0.26, RCol(0x1a2230))
        default:
            p.rect(-0.49, 0.1, 0.98, h * 0.55, col); p.rect(-0.3, h * 0.65, 0.6, h * 0.3, RCol(0x1a2230))
        }
        let lit = pose.brake || pose.night
        let red = lit ? RCol(0xff3a2e) : RCol(0xb0140e)
        p.rect(-0.46, h * 0.5, 0.2, 0.07, red); p.rect(0.26, h * 0.5, 0.2, 0.07, red)
    }
}

private struct Painter {
    let pen: Pen
    let col: RCol
    let pose: CarPose
    let detail: Bool
    let px: CGFloat
    var cg: CGContext { pen.cg }

    static let tyre = RCol(0x141417), carbon = RCol(0x18181b), trim = RCol(0x0d0d0f), chrome = RCol(0xc9ced6)
    var lit: Bool { pose.brake || pose.night }

    // MARK: primitives

    func path(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath()
        return p
    }
    func bounds(_ pts: [(CGFloat, CGFloat)]) -> CGRect {
        let xs = pts.map(\.0), ys = pts.map(\.1)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    /// Car paint: sky reflection on top, body colour, dark lower flank, plus a moving sheen in the garage.
    func paint(_ pts: [(CGFloat, CGFloat)], _ base: RCol? = nil) {
        let b = base ?? col
        let pth = path(pts), r = bounds(pts)
        if detail {
            pen.vgrad(r, [b.light(0.42), b.light(0.08), b, b.dark(0.28), b.dark(0.5)], path: pth)
            if let s = pose.sheen {
                cg.saveGState(); cg.addPath(pth); cg.clip(); cg.setBlendMode(.plusLighter)
                let x = s * 0.9
                pen.poly([(x - 0.06, r.minY), (x + 0.02, r.minY), (x + 0.16, r.maxY), (x + 0.08, r.maxY)], RCol.white.alpha(0.22))
                pen.poly([(x + 0.05, r.minY), (x + 0.07, r.minY), (x + 0.21, r.maxY), (x + 0.19, r.maxY)], RCol.white.alpha(0.14))
                cg.restoreGState()
            }
        } else {
            pen.poly(pts, b)
            pen.rect(r.minX, r.minY, r.width, r.height * 0.3, b.dark(0.3).alpha(0.6))
        }
    }
    func glass(_ pts: [(CGFloat, CGFloat)]) {
        let r = bounds(pts)
        if detail {
            pen.vgrad(r, [RCol(0x6f7f96), RCol(0x27303f), RCol(0x0c1018)], path: path(pts))
            cg.saveGState(); cg.addPath(path(pts)); cg.clip()
            pen.poly([(r.minX + r.width * 0.15, r.minY), (r.minX + r.width * 0.28, r.minY), (r.minX + r.width * 0.5, r.maxY), (r.minX + r.width * 0.37, r.maxY)], RCol.white.alpha(0.13))
            cg.restoreGState()
        } else {
            pen.poly(pts, RCol(0x1c2433))
        }
    }
    func highlight(_ pts: [(CGFloat, CGFloat)], _ a: CGFloat = 0.45) {
        guard detail else { return }
        pen.polyline(pts.map { CGPoint(x: $0.0, y: $0.1) }, RCol.white.alpha(a), max(px * 0.9, 0.006))
    }
    func light(_ pts: [(CGFloat, CGFloat)], glowAt: CGPoint, r: CGFloat = 0.11) {
        pen.poly(pts, lit ? RCol(0xff3b2f) : RCol(0xa3120c))
        if detail {
            let b = bounds(pts)
            pen.rect(b.minX, b.midY, b.width, b.height * 0.25, RCol(0xff8a7a).alpha(lit ? 0.7 : 0.35))
        }
        if lit { pen.glow(glowAt.x, glowAt.y, r * (pose.brake ? 1.2 : 0.8), RCol(0xff2a1a).alpha(pose.brake ? 0.75 : 0.45), sx: 1.4, sy: 0.8, add: true) }
    }
    func exhaust(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, oval: CGFloat = 1) {
        pen.ellipse(CGRect(x: x - r * oval, y: y - r, width: r * 2 * oval, height: r * 2), Self.chrome)
        pen.ellipse(CGRect(x: x - r * oval * 0.72, y: y - r * 0.72, width: r * 1.44 * oval, height: r * 1.44), RCol(0x0a0a0a))
        if detail { pen.ellipse(CGRect(x: x - r * oval * 0.9, y: y + r * 0.2, width: r * 1.8 * oval, height: r * 0.55), RCol.white.alpha(0.35)) }
    }
    func plate(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 0.17, _ h: CGFloat = 0.055) {
        pen.rect(x - w / 2, y, w, h, RCol(0xf1f1ea))
        guard detail else { return }
        pen.rect(x - w / 2, y, w * 0.12, h, RCol(0x1d4fb8))
        for k in 0..<5 { pen.rect(x - w * 0.3 + CGFloat(k) * w * 0.15, y + h * 0.28, w * 0.09, h * 0.44, RCol(0x222222)) }
    }
    func fins(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ n: Int) {
        guard detail else { return }
        for k in 0...n {
            let x = x0 + (x1 - x0) * CGFloat(k) / CGFloat(n)
            pen.rect(x - 0.005, y0, 0.01, y1 - y0, RCol(0x2c2c31))
        }
    }
    func mesh(_ r: CGRect) {
        pen.rrect(r, 0.01, Self.trim)
        guard detail else { return }
        var row = 0
        var y = r.minY + 0.012
        while y < r.maxY - 0.008 {
            var x = r.minX + 0.012 + (row % 2 == 0 ? 0 : 0.011)
            while x < r.maxX - 0.008 { pen.rect(x - 0.004, y - 0.003, 0.008, 0.006, RCol(0x2a2a2f)); x += 0.022 }
            y += 0.014; row += 1
        }
    }

    func shadow(_ h: CGFloat) {
        pen.glow(0, 0.015, 0.56, RCol.black.alpha(0.6), sx: 1, sy: 0.12)
    }

    func tyres(_ m: RaceCar.Model) {
        let spec: (x0: CGFloat, x1: CGFloat, h: CGFloat, knob: Bool)
        switch m {
        case .f1: spec = (0.27, 0.485, 0.26, false)
        case .defender: spec = (0.3, 0.47, 0.2, true)
        case .gwagon: spec = (0.31, 0.465, 0.19, true)
        case .m5: spec = (0.32, 0.47, 0.15, false)
        default: spec = (0.32, 0.475, 0.14, false)
        }
        for side: CGFloat in [-1, 1] {
            let x = side < 0 ? -spec.x1 : spec.x0, w = spec.x1 - spec.x0
            let r = CGRect(x: x, y: 0, width: w, height: spec.h)
            pen.rrect(r, w * 0.22, Self.tyre)
            guard detail else { continue }
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: r, cornerWidth: w * 0.22, cornerHeight: w * 0.22, transform: nil)); cg.clip()
            let step: CGFloat = spec.knob ? 0.034 : 0.026
            var y = -step + (pose.wheel * step).truncatingRemainder(dividingBy: step)
            var k = 0
            while y < spec.h {
                if spec.knob {
                    pen.rect(x + (k % 2 == 0 ? 0 : w * 0.5), y, w * 0.5, step * 0.45, RCol(0x2a2a2e))
                } else {
                    pen.rect(x + w * 0.12, y, w * 0.76, step * 0.22, RCol(0x26262a))
                }
                y += step; k += 1
            }
            pen.rect(side < 0 ? x : x + w * 0.82, 0, w * 0.18, spec.h, RCol.white.alpha(0.06))
            pen.rect(x, spec.h * 0.55, w, spec.h * 0.45, RCol.white.alpha(0.04))
            cg.restoreGState()
        }
    }

    func flame(_ x: CGFloat, _ y: CGFloat) {
        let f = 0.75 + 0.35 * CGFloat(sin(pose.time * 57 + Double(pose.seed) * 1.7)) * CGFloat(cos(pose.time * 23))
        pen.glow(x, y, 0.2 * f, RCol(0xff7a18).alpha(0.75), sx: 1, sy: 0.75, add: true)
        pen.glow(x, y, 0.09 * f, RCol(0x7fd8ff).alpha(0.95), add: true)
        pen.circle(x, y, 0.025 * f, RCol(0xf4fbff))
    }

    // MARK: models

    func lambo() {
        let body: [(CGFloat, CGFloat)] = [(-0.5, 0.1), (-0.495, 0.26), (-0.44, 0.325), (-0.31, 0.355), (0.31, 0.355), (0.44, 0.325), (0.495, 0.26), (0.5, 0.1)]
        paint(body)
        // engine deck with louvres + tiny rear screen
        let deck: [(CGFloat, CGFloat)] = [(-0.31, 0.355), (0.31, 0.355), (0.2, 0.432), (-0.2, 0.432)]
        paint(deck, col.dark(0.22))
        if detail { for k in 0..<4 { let y = 0.37 + CGFloat(k) * 0.015; pen.rect(-0.25 + CGFloat(k) * 0.02, y, 0.5 - CGFloat(k) * 0.04, 0.007, Self.trim) } }
        glass([(-0.17, 0.432), (0.17, 0.432), (0.115, 0.492), (-0.115, 0.492)])
        // deployable lip wing
        let wy = 0.352 + pose.wing * 0.04
        if pose.wing > 0.05 { pen.rect(-0.2, 0.35, 0.012, wy - 0.35, Self.trim); pen.rect(0.188, 0.35, 0.012, wy - 0.35, Self.trim) }
        pen.rect(-0.3, wy, 0.6, 0.016, col.dark(0.45))
        highlight([(-0.44, 0.322), (-0.31, 0.352), (0.31, 0.352), (0.44, 0.322)])
        // side grilles + diffuser
        mesh(CGRect(x: -0.47, y: 0.14, width: 0.17, height: 0.1)); mesh(CGRect(x: 0.3, y: 0.14, width: 0.17, height: 0.1))
        pen.poly([(-0.4, 0.03), (0.4, 0.03), (0.45, 0.135), (-0.45, 0.135)], Self.carbon)
        fins(-0.32, 0.32, 0.035, 0.125, 6)
        // hexagonal exhaust
        let hex: (CGFloat) -> [(CGFloat, CGFloat)] = { r in (0..<6).map { (cos(CGFloat($0) * .pi / 3) * r * 1.25, 0.12 + sin(CGFloat($0) * .pi / 3) * r) } }
        pen.poly(hex(0.05), Self.chrome); pen.poly(hex(0.036), RCol(0x0a0a0a))
        plate(0, 0.165, 0.15, 0.05)
        // Y-shaped lights inside hexagonal housings
        for s: CGFloat in [-1, 1] {
            let cx = s * 0.37, cy: CGFloat = 0.282
            let h: [(CGFloat, CGFloat)] = [(cx - 0.11, cy), (cx - 0.075, cy + 0.036), (cx + 0.075, cy + 0.036), (cx + 0.11, cy), (cx + 0.075, cy - 0.036), (cx - 0.075, cy - 0.036)]
            pen.poly(h, Self.trim)
            let red = lit ? RCol(0xff3b2f) : RCol(0xb5160f)
            let lw: CGFloat = detail ? 0.014 : 0.02
            pen.polyline([CGPoint(x: cx - 0.085, y: cy + 0.022), CGPoint(x: cx, y: cy), CGPoint(x: cx + 0.085, y: cy + 0.022)], red, lw)
            pen.line(CGPoint(x: cx, y: cy), CGPoint(x: cx, y: cy - 0.028), red, lw)
            if detail { pen.polyline(h.map { CGPoint(x: cx + ($0.0 - cx) * 0.86, y: cy + ($0.1 - cy) * 0.8) }, red.alpha(0.55), 0.006, closed: true) }
            if lit { pen.glow(cx, cy, 0.12, RCol(0xff2a1a).alpha(pose.brake ? 0.7 : 0.4), sx: 1.5, sy: 0.7, add: true) }
        }
    }

    func f1() {
        // suspension
        for s: CGFloat in [-1, 1] {
            pen.line(CGPoint(x: s * 0.12, y: 0.16), CGPoint(x: s * 0.28, y: 0.17), Self.carbon, 0.014)
            pen.line(CGPoint(x: s * 0.12, y: 0.08), CGPoint(x: s * 0.28, y: 0.08), Self.carbon, 0.014)
        }
        pen.poly([(-0.25, 0), (0.25, 0), (0.21, 0.085), (-0.21, 0.085)], Self.carbon)
        fins(-0.18, 0.18, 0.005, 0.08, 6)
        // helmet + halo behind the engine cover spine
        pen.circle(0, 0.365, 0.052, RCol(0xffd21f))
        if detail { pen.rect(-0.052, 0.36, 0.104, 0.016, RCol(0x1d4fb8)); pen.glow(-0.02, 0.385, 0.03, RCol.white.alpha(0.6)) }
        pen.arc(0, 0.305, 0.1, 0.25, .pi - 0.25, RCol(0x1c1c1f), 0.02)
        let cover: [(CGFloat, CGFloat)] = [(-0.15, 0.07), (0.15, 0.07), (0.13, 0.2), (0.05, 0.31), (-0.05, 0.31), (-0.13, 0.2)]
        paint(cover)
        pen.poly([(-0.022, 0.2), (0.022, 0.2), (0.016, 0.43), (-0.016, 0.43)], col.dark(0.15))
        if detail {
            pen.poly([(-0.03, 0.07), (0.03, 0.07), (0.02, 0.3), (-0.02, 0.3)], RCol.white.alpha(0.85))
            highlight([(-0.13, 0.2), (-0.05, 0.31), (0.05, 0.31), (0.13, 0.2)], 0.4)
        }
        pen.rect(-0.25, 0.175, 0.5, 0.026, Self.carbon)
        exhaust(0, 0.185, 0.022)
        // rain light (blinks; solid when braking)
        let blink = pose.brake || Int(pose.time * 4 + Double(pose.seed)) % 2 == 0
        pen.rect(-0.03, 0.11, 0.06, 0.035, blink ? RCol(0xff3b2f) : RCol(0x5a0d09))
        if blink { pen.glow(0, 0.128, 0.09, RCol(0xff2a1a).alpha(0.7), add: true) }
        // rear wing (DRS opens on nitro)
        for s: CGFloat in [-1, 1] { pen.rect(s < 0 ? -0.275 : 0.24, 0.17, 0.035, 0.3, col.dark(0.35)) }
        pen.rect(-0.245, 0.37, 0.49, 0.045, Self.carbon)
        let drs: CGFloat = pose.boost ? 0.025 : 0
        pen.rect(-0.245, 0.42 + drs, 0.49, 0.032, col)
        if detail {
            pen.rect(-0.245, 0.448 + drs, 0.49, 0.005, RCol.white.alpha(0.5))
            pen.rect(-0.12, 0.38, 0.24, 0.022, RCol.white.alpha(0.9))
            pen.rect(-0.1, 0.386, 0.2, 0.01, col)
        }
    }

    func defender() {
        pen.rect(-0.5, 0.52, 0.04, 0.07, Self.trim); pen.rect(0.46, 0.52, 0.04, 0.07, Self.trim)
        let body: [(CGFloat, CGFloat)] = [(-0.47, 0.13), (0.47, 0.13), (0.47, 0.655), (-0.47, 0.655)]
        paint(body)
        let roof = RCol(0xe9e5d8)
        paint([(-0.455, 0.655), (0.455, 0.655), (0.44, 0.79), (-0.44, 0.79)], roof)
        glass([(-0.17, 0.56), (0.25, 0.56), (0.25, 0.75), (-0.17, 0.75)])
        if detail {
            pen.rect(-0.215, 0.15, 0.006, 0.62, RCol.black.alpha(0.35))
            glass([(-0.42, 0.68), (-0.3, 0.68), (-0.3, 0.76), (-0.42, 0.76)]); glass([(0.31, 0.68), (0.42, 0.68), (0.42, 0.76), (0.31, 0.76)])
        }
        highlight([(-0.455, 0.652), (0.455, 0.652)], 0.35)
        // roof rack + cargo
        pen.rect(-0.43, 0.79, 0.86, 0.022, Self.trim)
        for x: CGFloat in [-0.42, -0.14, 0.14, 0.4] { pen.rect(x, 0.79, 0.02, 0.06, Self.trim) }
        pen.rect(-0.43, 0.84, 0.86, 0.012, Self.trim)
        pen.rrect(CGRect(x: -0.33, y: 0.812, width: 0.13, height: 0.075), 0.01, RCol(0x4b5a2c))
        pen.rrect(CGRect(x: -0.18, y: 0.812, width: 0.11, height: 0.07), 0.01, RCol(0xb7462a))
        pen.rrect(CGRect(x: 0.02, y: 0.812, width: 0.28, height: 0.055), 0.01, RCol(0x26282c))
        // bumper, step, hitch
        pen.rect(-0.48, 0.08, 0.96, 0.09, Self.trim)
        pen.rect(-0.12, 0.1, 0.24, 0.055, RCol(0x5b5e64))
        if detail { for k in 0..<6 { pen.rect(-0.11 + CGFloat(k) * 0.04, 0.115, 0.02, 0.02, RCol(0x8a8d93)) } }
        pen.circle(0, 0.07, 0.024, RCol(0x3a3a3e))
        // spare wheel on the door
        let sx: CGFloat = 0.04, sy: CGFloat = 0.37
        pen.circle(sx, sy, 0.155, Self.tyre)
        if detail { for k in 0..<14 { let a = CGFloat(k) / 14 * 2 * .pi + pose.wheel * 0.02; pen.circle(sx + cos(a) * 0.14, sy + sin(a) * 0.14, 0.018, RCol(0x2b2b30)) } }
        pen.circle(sx, sy, 0.088, RCol(0x8c9199))
        pen.circle(sx, sy, 0.07, RCol(0x5c6168))
        pen.circle(sx, sy, 0.03, RCol(0x2a2c30))
        if detail { for k in 0..<5 { let a = CGFloat(k) / 5 * 2 * .pi; pen.circle(sx + cos(a) * 0.05, sy + sin(a) * 0.05, 0.009, RCol(0xb9bec6)) } }
        // stacked lamps
        for s: CGFloat in [-1, 1] {
            let x = s < 0 ? -0.455 : 0.395
            pen.rrect(CGRect(x: x, y: 0.2, width: 0.06, height: 0.2), 0.012, Self.trim)
            light([(x + 0.008, 0.33), (x + 0.052, 0.33), (x + 0.052, 0.39), (x + 0.008, 0.39)], glowAt: CGPoint(x: x + 0.03, y: 0.36), r: 0.09)
            pen.rrect(CGRect(x: x + 0.008, y: 0.27, width: 0.044, height: 0.055), 0.008, RCol(0xf09a1c))
            pen.rrect(CGRect(x: x + 0.008, y: 0.21, width: 0.044, height: 0.055), 0.008, RCol(0xe8e8e2))
        }
    }

    func gwagon() {
        pen.rect(-0.5, 0.5, 0.045, 0.08, Self.trim); pen.rect(0.455, 0.5, 0.045, 0.08, Self.trim)
        paint([(-0.46, 0.13), (0.46, 0.13), (0.46, 0.6), (-0.46, 0.6)])
        pen.rect(-0.46, 0.595, 0.92, 0.014, Self.chrome.dark(0.2))
        paint([(-0.44, 0.61), (0.44, 0.61), (0.43, 0.86), (-0.43, 0.86)])
        paint([(-0.445, 0.86), (0.445, 0.86), (0.44, 0.9), (-0.44, 0.9)], col.light(0.12))
        glass([(-0.3, 0.635), (0.35, 0.635), (0.35, 0.84), (-0.3, 0.84)])
        if detail {
            glass([(-0.415, 0.635), (-0.36, 0.635), (-0.36, 0.84), (-0.415, 0.84)])
            pen.rect(0.4, 0.2, 0.025, 0.035, Self.chrome); pen.rect(0.4, 0.5, 0.025, 0.035, Self.chrome)
            pen.rect(-0.12, 0.555, 0.07, 0.014, Self.chrome)
            highlight([(-0.44, 0.858), (0.44, 0.858)], 0.4)
            highlight([(-0.46, 0.585), (0.46, 0.585)], 0.25)
        }
        // bumper + side pipes
        pen.rect(-0.47, 0.08, 0.94, 0.085, Self.trim)
        pen.rect(-0.15, 0.135, 0.3, 0.012, Self.chrome.alpha(0.7))
        for s: CGFloat in [-1, 1] { exhaust(s * 0.235, 0.105, 0.02); exhaust(s * 0.278, 0.105, 0.02) }
        // hard spare-wheel cover
        let sx: CGFloat = 0.035, sy: CGFloat = 0.38
        pen.circle(sx, sy, 0.16, Self.chrome)
        pen.circle(sx, sy, 0.142, col.dark(0.15))
        if detail {
            pen.glow(sx - 0.05, sy + 0.06, 0.09, RCol.white.alpha(0.18))
            pen.circle(sx, sy, 0.04, Self.chrome)
            pen.circle(sx, sy, 0.03, col.dark(0.3))
            for k in 0..<3 { let a = CGFloat(k) * 2 * .pi / 3 + .pi / 2; pen.line(CGPoint(x: sx, y: sy), CGPoint(x: sx + cos(a) * 0.03, y: sy + sin(a) * 0.03), Self.chrome, 0.006) }
        }
        plate(0.035, 0.175)
        for s: CGFloat in [-1, 1] {
            let x = s < 0 ? -0.455 : 0.38
            pen.rect(x, 0.29, 0.075, 0.18, Self.trim)
            light([(x + 0.008, 0.36), (x + 0.067, 0.36), (x + 0.067, 0.46), (x + 0.008, 0.46)], glowAt: CGPoint(x: x + 0.037, y: 0.41), r: 0.1)
            pen.rect(x + 0.008, 0.33, 0.059, 0.026, RCol(0xe6e6e0))
            pen.rect(x + 0.008, 0.3, 0.059, 0.026, RCol(0xf09a1c))
        }
    }

    func m5() {
        let body: [(CGFloat, CGFloat)] = [(-0.49, 0.11), (0.49, 0.11), (0.49, 0.33), (0.465, 0.39), (0.4, 0.42), (-0.4, 0.42), (-0.465, 0.39), (-0.49, 0.33)]
        paint(body)
        paint([(-0.4, 0.42), (0.4, 0.42), (0.27, 0.625), (-0.27, 0.625)])
        paint([(-0.27, 0.62), (0.27, 0.62), (0.245, 0.655), (-0.245, 0.655)], col.light(0.1))
        glass([(-0.33, 0.438), (0.33, 0.438), (0.235, 0.605), (-0.235, 0.605)])
        pen.poly([(-0.3, 0.418), (0.3, 0.418), (0.29, 0.438), (-0.29, 0.438)], Self.carbon)
        highlight([(-0.465, 0.388), (-0.4, 0.417), (0.4, 0.417), (0.465, 0.388)])
        highlight([(-0.49, 0.3), (0.49, 0.3)], 0.18)
        pen.poly([(-0.41, 0.045), (0.41, 0.045), (0.44, 0.145), (-0.44, 0.145)], Self.carbon)
        fins(-0.12, 0.12, 0.05, 0.13, 3)
        for x: CGFloat in [-0.29, -0.205, 0.205, 0.29] { exhaust(x, 0.098, 0.032) }
        plate(0, 0.17)
        if detail {
            pen.rect(0.2, 0.37, 0.016, 0.03, RCol(0x3fa2e8)); pen.rect(0.216, 0.37, 0.016, 0.03, RCol(0x2b2f8f)); pen.rect(0.232, 0.37, 0.016, 0.03, RCol(0xe0302a))
        }
        for s: CGFloat in [-1, 1] {
            let o: (CGFloat) -> CGFloat = { s * $0 }
            pen.poly([(o(0.49), 0.29), (o(0.29), 0.305), (o(0.275), 0.365), (o(0.45), 0.385), (o(0.49), 0.35)], Self.trim)
            let red = lit ? RCol(0xff3b2f) : RCol(0xc0180f)
            let lw: CGFloat = detail ? 0.016 : 0.024
            pen.polyline([CGPoint(x: o(0.3), y: 0.345), CGPoint(x: o(0.455), y: 0.35), CGPoint(x: o(0.465), y: 0.3)], red, lw)
            if detail { pen.rect(min(o(0.45), o(0.31)), 0.315, 0.14, 0.012, RCol(0x6a0d08)) }
            if lit { pen.glow(o(0.39), 0.34, 0.11, RCol(0xff2a1a).alpha(pose.brake ? 0.7 : 0.4), sx: 1.5, sy: 0.7, add: true) }
        }
    }

    func r8() {
        let body: [(CGFloat, CGFloat)] = [(-0.49, 0.11), (0.49, 0.11), (0.49, 0.3), (0.44, 0.37), (0.3, 0.4), (-0.3, 0.4), (-0.44, 0.37), (-0.49, 0.3)]
        paint(body)
        glass([(-0.3, 0.4), (0.3, 0.4), (0.18, 0.5), (-0.18, 0.5)])
        if detail { for k in 0..<3 { pen.rect(-0.2 + CGFloat(k) * 0.015, 0.415 + CGFloat(k) * 0.025, 0.4 - CGFloat(k) * 0.03, 0.006, RCol(0x8a2a22).alpha(0.6)) } }
        paint([(-0.18, 0.5), (0.18, 0.5), (0.165, 0.535), (-0.165, 0.535)], col.light(0.1))
        highlight([(-0.44, 0.368), (-0.3, 0.398), (0.3, 0.398), (0.44, 0.368)])
        // carbon side blades
        for s: CGFloat in [-1, 1] {
            pen.poly([(s * 0.5, 0.13), (s * 0.435, 0.13), (s * 0.42, 0.355), (s * 0.475, 0.335)], Self.carbon)
            if detail { pen.line(CGPoint(x: s * 0.425, y: 0.14), CGPoint(x: s * 0.418, y: 0.35), RCol.white.alpha(0.25), 0.006) }
        }
        mesh(CGRect(x: -0.41, y: 0.125, width: 0.82, height: 0.14))
        pen.poly([(-0.3, 0.03), (0.3, 0.03), (0.34, 0.115), (-0.34, 0.115)], Self.carbon)
        fins(-0.22, 0.22, 0.035, 0.11, 4)
        exhaust(-0.3, 0.155, 0.032, oval: 1.5); exhaust(0.3, 0.155, 0.032, oval: 1.5)
        plate(0, 0.2, 0.16, 0.05)
        // full-width light bar
        pen.rect(-0.42, 0.296, 0.84, 0.03, Self.trim)
        let red = lit ? RCol(0xff3b2f) : RCol(0xb5160f)
        pen.rect(-0.3, 0.306, 0.6, 0.008, red.alpha(0.85))
        for s: CGFloat in [-1, 1] {
            let x = s < 0 ? -0.44 : 0.3
            pen.poly([(x, 0.29), (x + 0.14, 0.29), (x + 0.14, 0.335), (x, 0.335)], Self.trim)
            if detail {
                for k in 0..<5 { pen.rect(x + 0.01 + CGFloat(k) * 0.026, 0.297, 0.018, 0.03, red) }
            } else {
                pen.rect(x + 0.01, 0.297, 0.12, 0.03, red)
            }
            if lit { pen.glow(x + 0.07, 0.31, 0.11, RCol(0xff2a1a).alpha(pose.brake ? 0.7 : 0.4), sx: 1.6, sy: 0.6, add: true) }
        }
        if lit { pen.glow(0, 0.31, 0.3, RCol(0xff2a1a).alpha(0.25), sx: 1.4, sy: 0.2, add: true) }
    }

    func laferrari() {
        let body: [(CGFloat, CGFloat)] = [(-0.5, 0.1), (-0.5, 0.22), (-0.485, 0.28), (-0.445, 0.32), (-0.38, 0.343), (-0.3, 0.338), (-0.22, 0.31),
                                          (0.22, 0.31), (0.3, 0.338), (0.38, 0.343), (0.445, 0.32), (0.485, 0.28), (0.5, 0.22), (0.5, 0.1)]
        paint(body)
        paint([(-0.22, 0.31), (0.22, 0.31), (0.13, 0.415), (-0.13, 0.415)], col.dark(0.3))
        if detail { for k in 0..<4 { pen.rect(-0.17 + CGFloat(k) * 0.02, 0.325 + CGFloat(k) * 0.02, 0.34 - CGFloat(k) * 0.04, 0.008, Self.trim) } }
        glass([(-0.12, 0.415), (0.12, 0.415), (0.09, 0.46), (-0.09, 0.46)])
        highlight([(-0.445, 0.318), (-0.38, 0.34), (-0.3, 0.335)], 0.5)
        highlight([(0.3, 0.335), (0.38, 0.34), (0.445, 0.318)], 0.5)
        // active wing rises with speed / braking
        let wy = 0.3 + pose.wing * 0.055
        if pose.wing > 0.05 { pen.rect(-0.13, 0.3, 0.012, wy - 0.3, Self.trim); pen.rect(0.118, 0.3, 0.012, wy - 0.3, Self.trim) }
        pen.rect(-0.22, wy, 0.44, 0.022, Self.carbon)
        // big diffuser + triple central exhaust
        mesh(CGRect(x: -0.47, y: 0.12, width: 0.12, height: 0.1)); mesh(CGRect(x: 0.35, y: 0.12, width: 0.12, height: 0.1))
        pen.poly([(-0.34, 0.02), (0.34, 0.02), (0.38, 0.215), (-0.38, 0.215)], Self.carbon)
        fins(-0.3, 0.3, 0.025, 0.2, 8)
        exhaust(-0.038, 0.155, 0.026); exhaust(0.038, 0.155, 0.026); exhaust(0, 0.198, 0.026)
        for s: CGFloat in [-1, 1] {
            let cx = s * 0.4
            pen.ellipse(CGRect(x: cx - 0.06, y: 0.255, width: 0.12, height: 0.065), Self.trim)
            pen.ellipse(CGRect(x: cx - 0.048, y: 0.263, width: 0.096, height: 0.049), lit ? RCol(0xff3b2f) : RCol(0xb5160f))
            if detail { pen.ellipse(CGRect(x: cx - 0.028, y: 0.275, width: 0.056, height: 0.025), lit ? RCol(0xffb0a0) : RCol(0x70100b)) }
            if lit { pen.glow(cx, 0.288, 0.11, RCol(0xff2a1a).alpha(pose.brake ? 0.75 : 0.4), sx: 1.3, sy: 0.8, add: true) }
        }
    }
}
