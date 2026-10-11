import AppKit

/// Pseudo-3D road renderer with uniform (unstretched) perspective, scenery, cars and per-camera overlays.
extension RaceGame {
    struct Proj { var x: CGFloat, y: CGFloat, w: CGFloat, s: CGFloat, z: CGFloat }

    static let drawDist = 170
    static let carWorldW: CGFloat = 380
    static let crowd: [RCol] = [0xff3b30, 0xffd21f, 0xffffff, 0x2f7fe0, 0xf09a1c, 0x3ddc84, 0xe0b090].map { RCol($0).mix(RCol(0x5f6c7d), 0.25) }
    static let sponsors = ["APEX", "VELOCE", "NITRO", "GRIDLINE", "TURBO", "KAPPA", "ORBIT", "FUEL+"]

    func fogAmount(_ z: CGFloat) -> CGFloat { pow(RK.clamp((z - 5000) / 29000), 0.8) * (theme.night ? 0.9 : 0.75) }

    func drawRace(_ c: Canvas) {
        let L = layout()
        let pen = Pen(cg: c.cg)
        pen.fill(c.bounds, RCol(0x07080c))
        for (p, v) in L.views.enumerated() where p < humanIdx.count { drawView(c, p, v) }
        for (p, g) in L.gauges.enumerated() where p < humanIdx.count { drawGauge(c, p, g) }
        drawMinimap(c, L.map)
        if let b = L.board { drawBoard(c, b) }
    }

    func drawView(_ c: Canvas, _ p: Int, _ v: CGRect) {
        let cg = c.cg, pen = Pen(cg: cg)
        let me = humanIdx[p]
        let r = racers[me]
        let mode = pov[p]
        let camH: CGFloat = [270, 165, 215][mode]
        let F = v.width * 0.6
        let pct = r.speed / r.spec.top
        cg.saveGState()
        cg.addPath(CGPath(roundedRect: v, cornerWidth: 3, cornerHeight: 3, transform: nil)); cg.clip()
        let sh = shake[p]
        let ox = sin(CGFloat(clock) * 71) * sh * 0.7, oy = sin(CGFloat(clock) * 53 + 1) * sh * 0.8
        cg.translateBy(x: ox, y: oy)
        let hor = v.minY + [20.5, 22, 20][mode] + (r.braking ? -0.3 : 0)
        let back: CGFloat = mode == 0 ? camH * F / (hor - v.minY - 1.6) : mode == 1 ? 60 : 300

        let segLen = RaceTrack.segLen
        let baseZ = r.d - back
        let baseIdx = Int(floor(baseZ / segLen))
        let frac = baseZ / segLen - CGFloat(baseIdx)
        let n0 = track.count
        func seg(_ k: Int) -> RaceSeg { track.segs[((k % n0) + n0) % n0] }
        let camY = track.height(r.d) + camH
        let camXw = camX[p] * roadW
        drawBackground(c, p, v, hor)

        // project boundaries
        var proj: [Proj] = []
        proj.reserveCapacity(Self.drawDist + 2)
        var x: CGFloat = 0, dx = -seg(baseIdx).curve * frac
        for n in 0...(Self.drawDist + 1) {
            let k = baseIdx + n
            let z = max(40, (CGFloat(n) - frac) * segLen)
            let s = F / z
            let wy = seg(k).y1
            proj.append(Proj(x: v.midX + (x - camXw) * s, y: hor + (wy - camY) * s, w: roadW * s, s: s, z: z))
            x += dx; dx += seg(k).curve
        }

        // ground + road, front to back with hill occlusion
        let th = theme
        var clip = [CGFloat](repeating: v.minY, count: Self.drawDist + 1)
        var maxY = v.minY - 1
        pen.fill(CGRect(x: v.minX, y: v.minY, width: v.width, height: hor - v.minY), th.grass.0.mix(th.fog, fogAmount(30000)))
        for n in 0..<Self.drawDist {
            let a = proj[n], b = proj[n + 1]
            clip[n] = maxY
            guard b.y > maxY, b.z > 60 else { continue }
            let k = baseIdx + n, s = seg(k), idx = ((k % n0) + n0) % n0
            let f = fogAmount(a.z)
            func fc(_ col: RCol) -> RCol { col.mix(th.fog, f) }
            let alt = (idx / 3) % 2 == 0
            let y1 = max(a.y, maxY - 0.5), y2 = b.y
            pen.rect(v.minX - 4, y1, v.width + 8, y2 - y1 + 0.4, fc(alt ? th.grass.0 : th.grass.1))
            let gpPit = th.scene == .gp && (idx < 70 || idx > n0 - 90)
            if gpPit { pen.quad(a.x - a.w * 4.5, a.x - a.w * 1.1, a.y, b.x - b.w * 4.5, b.x - b.w * 1.1, b.y, fc(RCol(0x4a4c52))) }
            if th.scene == .coast {
                pen.quad(a.x + a.w * 1.3, a.x + a.w * 1.75, a.y, b.x + b.w * 1.3, b.x + b.w * 1.75, b.y, fc(RCol(0xeedcab)))
                let sea = RCol(0x1f78b8).mix(RCol(0x56aee0), RK.clamp(a.z / 20000))
                pen.quad(a.x + a.w * 1.75, v.maxX + 600, a.y, b.x + b.w * 1.75, v.maxX + 600, b.y, fc(sea))
                if (idx * 7 + Int(clock * 3)) % 11 == 0 { pen.quad(a.x + a.w * 2.4, a.x + a.w * 3.2, a.y, b.x + b.w * 2.4, b.x + b.w * 3.2, b.y, fc(RCol(0xbfe6ff).alpha(0.7))) }
            }
            let ro = s.runoff
            pen.quad(a.x - a.w * ro, a.x + a.w * ro, a.y, b.x - b.w * ro, b.x + b.w * ro, b.y, fc(gpPit ? RCol(0x4a4c52) : th.runoff))
            if s.kerb {
                let kc = fc(idx % 2 == 0 ? th.kerb.0 : th.kerb.1)
                pen.quad(a.x - a.w * 1.13, a.x + a.w * 1.13, a.y, b.x - b.w * 1.13, b.x + b.w * 1.13, b.y, kc)
            }
            let rw: CGFloat = 1.0
            pen.quad(a.x - a.w * rw, a.x + a.w * rw, a.y, b.x - b.w * rw, b.x + b.w * rw, b.y, fc(alt ? th.road.0 : th.road.1))
            if !s.kerb || th.scene != .gp {
                pen.quad(a.x - a.w * 0.97, a.x - a.w * 0.93, a.y, b.x - b.w * 0.97, b.x - b.w * 0.93, b.y, fc(th.edge.alpha(0.9)))
                pen.quad(a.x + a.w * 0.93, a.x + a.w * 0.97, a.y, b.x + b.w * 0.93, b.x + b.w * 0.97, b.y, fc(th.edge.alpha(0.9)))
            }
            if th.scene != .gp, idx % 6 < 3 {
                pen.quad(a.x - a.w * 0.018, a.x + a.w * 0.018, a.y, b.x - b.w * 0.018, b.x + b.w * 0.018, b.y, fc(th.line))
            }
            if a.w > 25, idx % 2 == 0 {   // asphalt grain close to the camera
                let gx = RK.hash(idx) * 1.6 - 0.8
                pen.quad(a.x + a.w * gx, a.x + a.w * (gx + 0.12), a.y, b.x + b.w * gx, b.x + b.w * (gx + 0.12), b.y, RCol.black.alpha(0.05))
            }
            if idx < 2 {
                let cols = 10
                for col in 0..<cols {
                    for row in 0..<2 {
                        guard (col + row + idx * 2) % 2 == 0 else { continue }
                        let t0 = -1 + 2 * CGFloat(col) / CGFloat(cols), t1 = t0 + 2 / CGFloat(cols)
                        let ya = a.y + (b.y - a.y) * CGFloat(row) / 2, yb = a.y + (b.y - a.y) * CGFloat(row + 1) / 2
                        let xa = a.x + (b.x - a.x) * CGFloat(row) / 2, xb = a.x + (b.x - a.x) * CGFloat(row + 1) / 2
                        let wa = a.w + (b.w - a.w) * CGFloat(row) / 2, wb = a.w + (b.w - a.w) * CGFloat(row + 1) / 2
                        pen.quad(xa + wa * t0, xa + wa * t1, ya, xb + wb * t0, xb + wb * t1, yb, fc(RCol.white))
                    }
                }
                if idx == 0 { pen.quad(a.x - a.w, a.x + a.w, a.y, b.x - b.w, b.x + b.w, b.y, RCol(0xf6f6f6).alpha(0.25)) }
            }
            maxY = max(maxY, y2)
        }

        // cars per segment
        var carsAt: [Int: [Int]] = [:]
        let lapLen = track.length
        for (i, o) in racers.enumerated() {
            if i == me, mode != 0 { continue }
            var rel = (o.d - baseZ).truncatingRemainder(dividingBy: lapLen)
            if rel < 0 { rel += lapLen }
            let n = Int(rel / segLen)
            guard n < Self.drawDist - 1, rel > 120 else { continue }
            carsAt[n, default: []].append(i)
        }

        // back to front: walls, props, cars
        for n in stride(from: Self.drawDist - 1, through: 0, by: -1) {
            let a = proj[n], b = proj[n + 1]
            guard b.z > 80 else { continue }
            let k = baseIdx + n, s = seg(k), idx = ((k % n0) + n0) % n0
            let f = fogAmount(a.z)
            let cy = clip[n]
            cg.saveGState()
            cg.clip(to: CGRect(x: v.minX - 10, y: cy, width: v.width + 20, height: v.maxY - cy + 10))
            if let w = s.wallL { drawWall(pen, c, w, -1, a, b, idx, f) }
            if let w = s.wallR { drawWall(pen, c, w, 1, a, b, idx, f) }
            for pr in s.props.sorted(by: { abs($0.x) > abs($1.x) }) { drawProp(pen, c, pr, a, f, idx, v) }
            if let list = carsAt[n] {
                for i in list.sorted(by: { racers[$0].d < racers[$1].d }) {
                    let o = racers[i]
                    var rel = (o.d - baseZ).truncatingRemainder(dividingBy: lapLen)
                    if rel < 0 { rel += lapLen }
                    let t = rel / segLen - CGFloat(n)
                    let sc = a.s + (b.s - a.s) * t
                    let cx = a.x + (b.x - a.x) * t + o.x * roadW * sc
                    let gy = a.y + (b.y - a.y) * t
                    let w = Self.carWorldW * sc
                    let pose = CarPose(steer: o.steer, brake: o.braking, boost: o.boosting, wheel: o.wheel, wing: o.wing, time: clock, night: th.night, seed: i)
                    if f > 0.02 { cg.setAlpha(1 - f * 0.6) }
                    CarArt.draw(c, o.spec, paint: o.paint, cx: cx, by: gy, w: w, pose: pose)
                    cg.setAlpha(1)
                    if i == me, o.boosting { pen.glow(cx, gy + w * 0.12, w * 0.5, RCol(0x7fd8ff).alpha(0.25), sx: 1.4, sy: 0.6, add: true) }
                }
            }
            cg.restoreGState()
        }

        if mode == 1 { drawCockpit(c, r, v, p) } else if mode == 2 { drawHood(c, r, v) }
        if pct > 0.72 || r.boosting { drawSpeedLines(pen, v, hor, r.boosting ? 1 : (pct - 0.72) / 0.28, p) }
        if r.boosting { pen.hgrad(CGRect(x: v.minX, y: v.minY, width: 26, height: v.height), [RCol(0x5fd0ff).alpha(0.28), RCol(0x5fd0ff).alpha(0)])
            pen.hgrad(CGRect(x: v.maxX - 26, y: v.minY, width: 26, height: v.height), [RCol(0x5fd0ff).alpha(0), RCol(0x5fd0ff).alpha(0.28)]) }
        cg.restoreGState()

        drawViewOverlay(c, p, v)
        drawParticles(c, p, v)
        pen.strokeRR(v.insetBy(dx: 0.5, dy: 0.5), 3, RCol.white.alpha(0.12), 1)
    }

    // MARK: background

    func drawBackground(_ c: Canvas, _ p: Int, _ v: CGRect, _ hor: CGFloat) {
        let pen = Pen(cg: c.cg), th = theme
        let sky = CGRect(x: v.minX, y: hor - 2, width: v.width, height: v.maxY - hor + 4)
        pen.vgrad(sky, th.sky)
        let off = bgOffset[p]
        func ridge(_ par: CGFloat, _ base: CGFloat, _ amp: CGFloat, _ freq: CGFloat, _ seed: CGFloat, _ col: RCol, peaks: Bool = false, snow: RCol? = nil) {
            var pts: [CGPoint] = [CGPoint(x: v.minX - 2, y: hor - 3)]
            var top: [CGPoint] = []
            var xx = v.minX - 2
            while xx <= v.maxX + 3 {
                let u = (xx - v.minX + off * par) * freq + seed
                var h = sin(u) * 0.5 + sin(u * 2.3 + 1.7) * 0.3 + sin(u * 5.1 + 0.3) * 0.2
                if peaks { h = abs(sin(u * 0.9)) * 0.9 + abs(sin(u * 2.1 + 1)) * 0.45 - 0.35 }
                let y = hor + base + amp * h
                pts.append(CGPoint(x: xx, y: y)); top.append(CGPoint(x: xx, y: y))
                xx += 2
            }
            pts.append(CGPoint(x: v.maxX + 3, y: hor - 3))
            pen.poly(pts, col)
            if let snow {
                let cap = top.map { CGPoint(x: $0.x, y: max($0.y - 1.8 - (hor + base + amp * 0.6 > $0.y ? 4 : 0), hor + base + amp * 0.35)) }
                for i in 0..<(top.count - 1) where top[i].y > hor + base + amp * 0.38 {
                    pen.poly([top[i], top[i + 1], cap[i + 1], cap[i]], snow)
                }
            }
        }
        switch th.scene {
        case .gp:
            let sx = v.minX + v.width * 0.78 - (off * 0.05).truncatingRemainder(dividingBy: v.width)
            pen.glow(sx, hor + 7, 10, RCol(0xfff4d0).alpha(0.6))
            for k in 0..<4 {
                let cx = v.minX + ((CGFloat(k) * 83 + 30 - off * 0.15).truncatingRemainder(dividingBy: v.width + 60) + v.width + 60).truncatingRemainder(dividingBy: v.width + 60) - 30
                let cy = hor + 5 + CGFloat(k % 2) * 3
                pen.glow(cx, cy, 9, RCol.white.alpha(0.7), sx: 1.8, sy: 0.35)
            }
            ridge(0.25, 1.2, 1.6, 0.03, 0, RCol(0x8fb3cf))
            ridge(0.5, 0.2, 1.2, 0.07, 2, RCol(0x3f7a4a))
            ridge(0.6, -0.6, 0.6, 0.31, 5, RCol(0x2e6a3a))
        case .coast:
            pen.glow(v.minX + v.width * 0.3 - (off * 0.05).truncatingRemainder(dividingBy: v.width), hor + 3, 14, RCol(0xffd9a0).alpha(0.8))
            pen.rect(v.minX, hor - 1, v.width, 2.5, RCol(0x3f8fcf))
            for k in 0..<10 {
                let gx = v.minX + RK.hash(k * 3 + Int(clock * 2)) * v.width
                pen.rect(gx, hor - 0.3 + RK.hash(k) * 1.5, 3 + RK.hash(k * 5) * 4, 0.5, RCol.white.alpha(0.6))
            }
            ridge(0.3, 0.8, 3.5, 0.025, 1, RCol(0x9cb0b8))
            ridge(0.45, -0.2, 1.3, 0.06, 3, RCol(0x6e8a66))
        case .alpine:
            pen.glow(v.minX + v.width * 0.7, hor + 8, 9, RCol.white.alpha(0.5))
            ridge(0.12, 2.5, 6.5, 0.022, 0.5, RCol(0x8ea4c4), peaks: true, snow: RCol(0xf4f8ff))
            ridge(0.28, 0.5, 4.2, 0.04, 2.2, RCol(0x5d7290), peaks: true, snow: RCol(0xe6eef8))
            ridge(0.55, -0.8, 1.3, 0.2, 4, RCol(0x2f4a3a))
        case .night:
            for k in 0..<26 {
                let sx = v.minX + RK.hash(k * 11) * v.width, sy = hor + 3 + RK.hash(k * 17) * (v.maxY - hor - 3)
                pen.rect(sx, sy, 0.6, 0.6, RCol.white.alpha(0.3 + 0.4 * RK.hash(k + Int(clock * 2) % 3)))
            }
            pen.circle(v.minX + v.width * 0.82, v.maxY - 5, 2.6, RCol(0xf3ecd8))
            pen.glow(v.minX + v.width * 0.82, v.maxY - 5, 8, RCol(0xf3ecd8).alpha(0.25))
            pen.glow(v.midX, hor, v.width * 0.5, RCol(0x6a4cff).alpha(0.18), sx: 1, sy: 0.12)
            for layer in 0..<2 {
                let par: CGFloat = layer == 0 ? 0.2 : 0.45
                var xx = v.minX - 20 - (off * par).truncatingRemainder(dividingBy: 20)
                var k = Int((off * par) / 20)
                while xx < v.maxX + 20 {
                    let bw = 9 + RK.hash(k * 7 + layer) * 10, bh = (layer == 0 ? 5 : 3) + RK.hash(k * 13 + layer) * (layer == 0 ? 6 : 4)
                    let col = layer == 0 ? RCol(0x161a33) : RCol(0x0d1024)
                    pen.rect(xx, hor - 1, bw, bh + 1, col)
                    if layer == 1 {
                        for wy in stride(from: hor + 1, to: hor + bh - 0.5, by: 1.4) {
                            for wx in stride(from: xx + 1, to: xx + bw - 1, by: 1.6) where RK.hash(Int(wx * 3 + wy * 7) + k) > 0.6 {
                                pen.rect(wx, wy, 0.7, 0.6, RCol(0xffd58a).alpha(0.7))
                            }
                        }
                    }
                    xx += bw + 1; k += 1
                }
            }
        }
        let haze = CGRect(x: v.minX, y: hor - 1, width: v.width, height: 5)
        pen.vgrad(haze, [th.fog.alpha(0), th.fog.alpha(th.night ? 0.25 : 0.55)])
    }

    // MARK: walls

    func drawWall(_ pen: Pen, _ c: Canvas, _ w: RaceWall, _ side: CGFloat, _ a: Proj, _ b: Proj, _ idx: Int, _ f: CGFloat) {
        let xa = a.x + side * w.x * a.w, xb = b.x + side * w.x * b.w
        let ha = w.h * a.s, hb = w.h * b.s
        func fc(_ col: RCol) -> RCol { col.mix(theme.fog, f) }
        let face = [CGPoint(x: xa, y: a.y), CGPoint(x: xb, y: b.y), CGPoint(x: xb, y: b.y + hb), CGPoint(x: xa, y: a.y + ha)]
        func band(_ t0: CGFloat, _ t1: CGFloat, _ col: RCol) {
            pen.poly([CGPoint(x: xa, y: a.y + ha * t0), CGPoint(x: xb, y: b.y + hb * t0), CGPoint(x: xb, y: b.y + hb * t1), CGPoint(x: xa, y: a.y + ha * t1)], fc(col))
        }
        switch w.kind {
        case .pit:
            pen.poly(face, fc(RCol(0xe9ecef)))
            if idx % 6 < 3 { band(0.35, 0.8, RCol([0xe10600, 0x1d4fb8, 0x111111][(idx / 6) % 3])) }
            band(0.9, 1, RCol(0x9aa0a8))
        case .armco:
            pen.poly(face, fc(RCol(0x8e959e)))
            band(0.45, 0.75, RCol(0xd5dbe2)); band(0, 0.15, RCol(0x5b6068))
        case .fence:
            band(0, 0.35, RCol(0xb9bfc6))
            band(0.35, 1, RCol(0x9aa3ad).alpha(0.28))
            if idx % 2 == 0 { pen.line(CGPoint(x: xa, y: a.y), CGPoint(x: xa, y: a.y + ha), fc(RCol(0x6d747c)), max(0.5, a.s * 30)) }
        case .stand:
            pen.poly(face, fc(RCol(0x5f6c7d)))
            band(0, 0.14, RCol(0xdfe3e8))
            band(0.92, 1, RCol(0x2c3440))
            if ha > 5 {
                // Crowd dots: bucket by shirt colour and fill each bucket in one call (this was the hottest path).
                let span = abs(xb - xa)
                let cols = max(2, min(160, Int(span / 1.1)))
                let rows = max(3, min(14, Int(ha * 0.72 / 1.2)))
                let sway = CGFloat(clock)
                var buckets = [[CGRect]](repeating: [], count: Self.crowd.count)
                for row in 0..<rows {
                    let ty = 0.18 + 0.7 * CGFloat(row) / CGFloat(rows)
                    for k in 0..<cols {
                        let h = RK.hash(idx * 97 + row * 13 + k)
                        guard h > 0.18 else { continue }
                        let t = (CGFloat(k) + 0.5) / CGFloat(cols)
                        let px = xa + (xb - xa) * t
                        let base = a.y + (b.y - a.y) * t
                        let hh = ha + (hb - ha) * t
                        let jump: CGFloat = sin(sway * (6 + h * 5) + h * 40) > 0.8 ? 0.35 : 0
                        let sz = min(0.9, max(0.5, hh * 0.05))
                        buckets[Int(h * 70) % Self.crowd.count].append(CGRect(x: px - sz / 2, y: base + hh * ty + jump, width: sz, height: sz))
                    }
                }
                for (i, rs) in buckets.enumerated() where !rs.isEmpty { pen.set(fc(Self.crowd[i])); c.cg.fill(rs) }
            } else {
                band(0.2, 0.85, RCol(0x9c8f86))
            }
        case .rock:
            pen.poly(face, fc(RCol(0x7d7468).mix(RCol(0x5c554c), RK.hash(idx / 3))))
            if theme.scene == .alpine { band(0.85, 1, RCol(0xf2f6fb)) }
            band(0, 0.08, RCol(0x4a443d))
        case .snow:
            pen.poly(face, fc(RCol(0xf3f7fc)))
            band(0, 0.3, RCol(0xd6e1ee))
        case .building:
            let base = RCol(0x1a1d2c).mix(RCol(0x2a2236), RK.hash(idx / 18))
            pen.poly(face, fc(base))
            if ha > 3 {
                for fl in stride(from: CGFloat(0.12), to: 0.95, by: 0.11) where RK.hash(idx * 31 + Int(fl * 100)) > 0.45 {
                    band(fl, fl + 0.045, RCol(0xffd58a).alpha(0.75))
                }
            }
            band(0, 0.06, RCol(0x0c0d14))
        default:
            pen.poly(face, fc(RCol(0x777777)))
        }
    }

    // MARK: props

    func drawProp(_ pen: Pen, _ c: Canvas, _ pr: RaceProp, _ a: Proj, _ f: CGFloat, _ idx: Int, _ v: CGRect) {
        let cg = c.cg
        let gx = a.x + pr.x * a.w, gy = a.y
        func fc(_ col: RCol) -> RCol { col.mix(theme.fog, f) }
        if pr.kind == .gantry { drawGantry(pen, a, f); return }
        let size: CGFloat
        switch pr.kind {
        case .tree: size = 1700 + pr.v * 600
        case .palm: size = 2000 + pr.v * 700
        case .pine: size = 1500 + pr.v * 900
        case .rock: size = 500 + pr.v * 400
        case .tyres: size = 420
        case .board: size = 900
        case .marshal: size = 420
        case .pole: size = 300
        case .lamp: size = 1700
        case .chalet: size = 1600
        case .hut: size = 700
        case .lighthouse: size = 3600
        case .chevron: size = 380
        case .bush: size = 500 + pr.v * 300
        case .banner: size = 900
        case .gantry: size = 0
        }
        let px = size * a.s
        guard px > 1, gx > v.minX - px * 1.5, gx < v.maxX + px * 1.5 else { return }
        if pr.kind == .board, px > 26 {
            let r = CGRect(x: gx - px / 2, y: gy, width: px, height: px * 0.3)
            let cols = [RCol(0xe10600), RCol(0x111111), RCol(0x1d4fb8), RCol(0xffd21f), RCol(0x00a19c)]
            let bg = cols[Int(pr.v * 50) % cols.count]
            pen.rect(r.minX, r.minY, r.width, r.height, fc(bg))
            let txt = bg.r + bg.g > 1.4 ? RCol(0x111111) : RCol.white
            c.rtext(Self.sponsors[Int(pr.v * 80) % Self.sponsors.count], r.midX, r.minY + r.height * 0.12, r.height * 0.62, fc(txt), .black, align: .center)
            return
        }
        cg.saveGState()
        cg.translateBy(x: gx, y: gy); cg.scaleBy(x: px, y: px)
        let detail = px > 8
        switch pr.kind {
        case .tree:
            pen.rect(-0.04, 0, 0.08, 0.35, fc(RCol(0x5a3d26)))
            let g = RCol(0x2f7a35).mix(RCol(0x4c8f2c), pr.v)
            pen.circle(0, 0.62, 0.3, fc(g.dark(0.15))); pen.circle(-0.17, 0.5, 0.22, fc(g.dark(0.25))); pen.circle(0.17, 0.52, 0.22, fc(g))
            if detail { pen.circle(-0.06, 0.72, 0.16, fc(g.light(0.18))) }
        case .palm:
            let lean = (pr.v - 0.5) * 0.4
            pen.polyline([CGPoint(x: 0, y: 0), CGPoint(x: lean * 0.4, y: 0.45), CGPoint(x: lean, y: 0.86)], fc(RCol(0x8a6a44)), 0.045)
            let top = CGPoint(x: lean, y: 0.86)
            for k in 0..<7 {
                let ang = CGFloat(k) / 7 * .pi * 2 + pr.v + CGFloat(sin(clock * 1.3 + Double(idx))) * 0.05
                let ex = top.x + cos(ang) * 0.32, ey = top.y + sin(ang) * 0.12 - 0.06
                pen.polyline([top, CGPoint(x: top.x + cos(ang) * 0.2, y: top.y + 0.05 + sin(ang) * 0.06), CGPoint(x: ex, y: ey)], fc(RCol(0x2e8a3e).mix(RCol(0x58a83a), CGFloat(k % 2))), 0.05)
            }
            if detail { pen.circle(top.x, top.y - 0.02, 0.03, fc(RCol(0x5a3d1e))) }
        case .pine:
            pen.rect(-0.03, 0, 0.06, 0.15, fc(RCol(0x4a3020)))
            let g = RCol(0x1f4f36).mix(RCol(0x2d6a42), pr.v)
            for k in 0..<3 {
                let y0 = 0.12 + CGFloat(k) * 0.26, hw = 0.3 - CGFloat(k) * 0.07
                pen.poly([(-hw, y0), (hw, y0), (0, y0 + 0.42)], fc(g.dark(CGFloat(2 - k) * 0.08)))
                if theme.scene == .alpine { pen.poly([(-hw * 0.4, y0 + 0.25), (hw * 0.4, y0 + 0.25), (0, y0 + 0.42)], fc(RCol(0xf4f8fd))) }
            }
        case .rock:
            pen.poly([(-0.5, 0), (-0.42, 0.35), (-0.12, 0.6), (0.2, 0.52), (0.48, 0.25), (0.5, 0)], fc(RCol(0x7c766e)))
            pen.poly([(-0.42, 0.35), (-0.12, 0.6), (0.0, 0.3)], fc(RCol(0x9a948b)))
            if theme.scene == .alpine { pen.poly([(-0.2, 0.55), (-0.12, 0.6), (0.2, 0.52), (0.05, 0.5)], fc(RCol.white)) }
        case .tyres:
            for row in 0..<2 {
                for k in 0..<4 {
                    let col = (k + row) % 2 == 0 ? RCol(0x1b1b1e) : (pr.v > 0.5 ? RCol(0xe0221c) : RCol(0xf2f2f2))
                    pen.ellipse(CGRect(x: -0.6 + CGFloat(k) * 0.3, y: CGFloat(row) * 0.28, width: 0.3, height: 0.3), fc(col))
                }
            }
            if detail { pen.rect(-0.6, 0.53, 1.2, 0.05, fc(RCol(0x0e0e10))) }
        case .board:
            let cols = [RCol(0xe10600), RCol(0x111111), RCol(0x1d4fb8), RCol(0xffd21f), RCol(0x00a19c)]
            pen.rect(-0.5, 0, 1, 0.3, fc(cols[Int(pr.v * 50) % cols.count])); pen.rect(-0.3, 0.1, 0.6, 0.1, fc(RCol.white.alpha(0.8)))
        case .marshal:
            pen.rect(-0.25, 0, 0.5, 0.6, fc(RCol(0xf09a1c))); pen.rect(-0.2, 0.35, 0.4, 0.18, fc(RCol(0x2a2a2e)))
            let wave = CGFloat(sin(clock * 9 + Double(idx))) * 0.08
            pen.line(CGPoint(x: 0.2, y: 0.6), CGPoint(x: 0.35, y: 1.05), fc(RCol(0x333333)), 0.03)
            pen.poly([(0.35, 1.05), (0.75, 1.0 + wave), (0.72, 0.8 + wave), (0.35, 0.85)], fc(RCol(0x2fbf4a)))
        case .pole:
            for k in 0..<5 { pen.rect(-0.04, CGFloat(k) * 0.4, 0.08, 0.4, fc(k % 2 == 0 ? RCol(0xe0221c) : RCol.white)) }
        case .lamp:
            let dir: CGFloat = pr.x < 0 ? 1 : -1
            pen.rect(-0.02, 0, 0.04, 1, fc(RCol(0x4a4f57)))
            pen.line(CGPoint(x: 0, y: 1), CGPoint(x: dir * 0.3, y: 1.05), fc(RCol(0x4a4f57)), 0.035)
            pen.rect(dir * 0.3 - 0.07, 1.0, 0.14, 0.04, fc(RCol(0xfff3c4)))
            if theme.night { pen.glow(dir * 0.3, 0.98, 0.35, RCol(0xffd88a).alpha(0.4), sx: 1, sy: 1.3, add: true) }
        case .chalet:
            pen.rect(-0.45, 0, 0.9, 0.5, fc(RCol(0x7a4a2a)))
            pen.poly([(-0.6, 0.48), (0.6, 0.48), (0, 0.9)], fc(RCol(0xf6f9fd)))
            for k in 0..<3 { pen.rect(-0.33 + CGFloat(k) * 0.25, 0.18, 0.13, 0.15, fc(RCol(0xffd27a))) }
        case .hut:
            for k in 0..<5 { pen.rect(-0.5 + CGFloat(k) * 0.2, 0, 0.2, 0.7, fc(k % 2 == 0 ? RCol(0x2f9ad8) : RCol.white)) }
            pen.poly([(-0.6, 0.68), (0.6, 0.68), (0, 1.0)], fc(RCol(0xd8302b)))
        case .lighthouse:
            for k in 0..<5 { pen.poly([(-0.12 + CGFloat(k) * 0.008, CGFloat(k) * 0.16), (0.12 - CGFloat(k) * 0.008, CGFloat(k) * 0.16), (0.12 - CGFloat(k + 1) * 0.008, CGFloat(k + 1) * 0.16), (-0.12 + CGFloat(k + 1) * 0.008, CGFloat(k + 1) * 0.16)], fc(k % 2 == 0 ? RCol.white : RCol(0xd8302b))) }
            pen.rect(-0.07, 0.8, 0.14, 0.1, fc(RCol(0xfff1b0))); pen.poly([(-0.1, 0.9), (0.1, 0.9), (0, 0.98)], fc(RCol(0x2a2a2e)))
        case .chevron:
            pen.rect(-0.04, 0, 0.08, 0.5, fc(RCol(0x555555)))
            pen.rect(-0.5, 0.5, 1, 0.45, fc(RCol(0x111111)))
            let d: CGFloat = pr.v > 0.5 ? 1 : -1
            for k in 0..<3 {
                let cx = -0.3 + CGFloat(k) * 0.3
                pen.polyline([CGPoint(x: cx - d * 0.08, y: 0.58), CGPoint(x: cx + d * 0.08, y: 0.725), CGPoint(x: cx - d * 0.08, y: 0.87)], fc(RCol(0xffd21f)), 0.08)
            }
        case .bush:
            let g = theme.scene == .coast ? RCol(0x6f8f3a) : RCol(0x3f7a35)
            pen.ellipse(CGRect(x: -0.5, y: 0, width: 0.6, height: 0.5), fc(g.dark(0.15))); pen.ellipse(CGRect(x: -0.15, y: 0, width: 0.65, height: 0.6), fc(g))
        case .banner:
            pen.rect(-0.02, 0, 0.04, 1.2, fc(RCol(0x666666)))
            let cols = [RCol(0xe10600), RCol(0x1d4fb8), RCol(0xffd21f)]
            pen.rect(0.02, 0.5, 0.25, 0.68, fc(cols[Int(pr.v * 30) % 3])); pen.rect(0.06, 0.6, 0.17, 0.12, fc(RCol.white))
        case .gantry: break
        }
        cg.restoreGState()
    }

    /// Start/finish gantry spanning the track with the five-light start system.
    func drawGantry(_ pen: Pen, _ a: Proj, _ f: CGFloat) {
        let span: CGFloat = theme.scene == .gp ? 1.55 : 1.4
        let l = a.x - a.w * span, r = a.x + a.w * span
        let h0 = a.y + 1500 * a.s, h1 = a.y + 1850 * a.s
        let post = max(0.6, 90 * a.s)
        let col = RCol(0x2a2d33).mix(theme.fog, f)
        pen.rect(l - post / 2, a.y, post, h1 - a.y, col); pen.rect(r - post / 2, a.y, post, h1 - a.y, col)
        pen.rect(l, h0, r - l, h1 - h0, col)
        if a.w > 30 {
            let brand = theme.scene == .gp ? RCol(0xe10600) : RCol(0x1d4fb8)
            pen.rect(l + (r - l) * 0.04, h0 + (h1 - h0) * 0.15, (r - l) * 0.24, (h1 - h0) * 0.7, brand.mix(theme.fog, f))
            pen.rect(r - (r - l) * 0.28, h0 + (h1 - h0) * 0.15, (r - l) * 0.24, (h1 - h0) * 0.7, brand.mix(theme.fog, f))
        }
        let lightsOn = phase == .countdown ? min(5, Int(countT / 0.6)) : 0
        let green = phase == .race && raceTime < 1.2
        for k in 0..<5 {
            let cx = a.x + (CGFloat(k) - 2) * (r - l) * 0.075, cy = (h0 + h1) / 2, rr = max(0.4, (h1 - h0) * 0.28)
            let on = k < lightsOn
            pen.circle(cx, cy, rr * 1.25, RCol(0x0b0b0d))
            pen.circle(cx, cy, rr, on ? RCol(0xff2a1a) : green ? RCol(0x3ddc84) : RCol(0x3a1612))
            if on || green { pen.glow(cx, cy, rr * 3.5, (on ? RCol(0xff2a1a) : RCol(0x3ddc84)).alpha(0.55), add: true) }
        }
    }

    // MARK: overlays

    func drawSpeedLines(_ pen: Pen, _ v: CGRect, _ hor: CGFloat, _ amt: CGFloat, _ p: Int) {
        let vp = CGPoint(x: v.midX, y: hor)
        let tick = Int(clock * 30)
        for k in 0..<14 {
            let h = RK.hash(k * 29 + tick * 7 + p * 101)
            let ang = (h * 2 - 1) * .pi * 0.92 + (h > 0.5 ? 0 : .pi)
            let dir = CGPoint(x: cos(ang), y: sin(ang) * 0.32)
            let r0 = v.width * (0.28 + RK.hash(k + tick) * 0.15), r1 = r0 + v.width * (0.1 + 0.12 * amt)
            pen.line(CGPoint(x: vp.x + dir.x * r0, y: vp.y + dir.y * r0), CGPoint(x: vp.x + dir.x * r1, y: vp.y + dir.y * r1), RCol.white.alpha(0.22 * amt), 0.6)
        }
    }

    func drawCockpit(_ c: Canvas, _ r: Racer, _ v: CGRect, _ p: Int) {
        let pen = Pen(cg: c.cg)
        let accent = r.paint
        let f1 = r.spec.model == .f1
        if f1 {
            pen.poly([(v.midX - 1.5, v.minY + 6), (v.midX + 1.5, v.minY + 6), (v.midX + 1, v.maxY + 1), (v.midX - 1, v.maxY + 1)], RCol(0x18181b))
            c.cg.saveGState()
            pen.arc(v.midX, v.minY - 10, 38, 0.55, .pi - 0.55, RCol(0x18181b), 3)
            c.cg.restoreGState()
            pen.poly([(v.minX, v.minY), (v.maxX, v.minY), (v.maxX, v.minY + 4), (v.midX + 40, v.minY + 7), (v.midX - 40, v.minY + 7), (v.minX, v.minY + 4)], accent.dark(0.2))
            pen.poly([(v.midX - 28, v.minY + 6.8), (v.midX + 28, v.minY + 6.8), (v.midX + 22, v.minY + 8), (v.midX - 22, v.minY + 8)], RCol.white.alpha(0.25))
        } else {
            // A-pillars + roof + dash
            pen.poly([(v.minX, v.maxY), (v.minX + 26, v.maxY), (v.minX + 6, v.minY + 8), (v.minX, v.minY + 8)], RCol(0x0e0f12))
            pen.poly([(v.maxX, v.maxY), (v.maxX - 26, v.maxY), (v.maxX - 6, v.minY + 8), (v.maxX, v.minY + 8)], RCol(0x0e0f12))
            pen.rect(v.minX, v.maxY - 2.2, v.width, 2.2, RCol(0x15161a))
            pen.rrect(CGRect(x: v.midX - 16, y: v.maxY - 5.2, width: 32, height: 3.6), 1.4, RCol(0x0b0b0e))
            pen.vgrad(CGRect(x: v.midX - 15, y: v.maxY - 4.7, width: 30, height: 2.6), [theme.sky[1].dark(0.2), theme.road.0.dark(0.3)])
            let dash = CGMutablePath()
            dash.move(to: CGPoint(x: v.minX, y: v.minY)); dash.addLine(to: CGPoint(x: v.minX, y: v.minY + 8))
            dash.addQuadCurve(to: CGPoint(x: v.maxX, y: v.minY + 8), control: CGPoint(x: v.midX, y: v.minY + 11.5))
            dash.addLine(to: CGPoint(x: v.maxX, y: v.minY)); dash.closeSubpath()
            pen.vgrad(CGRect(x: v.minX, y: v.minY, width: v.width, height: 11), [RCol(0x2a2c32), RCol(0x101114)], path: dash)
            pen.polyline([CGPoint(x: v.minX + 30, y: v.minY + 9.1), CGPoint(x: v.midX, y: v.minY + 9.9), CGPoint(x: v.maxX - 30, y: v.minY + 9.1)], accent.alpha(0.55), 0.5)
            // tacho strip on the dash
            let pct = r.speed / r.spec.top
            for k in 0..<12 {
                let on = CGFloat(k) / 12 < pct
                let col = k < 8 ? RCol.go : k < 10 ? RCol.gold : RCol.red
                pen.rect(v.midX - 18 + CGFloat(k) * 3, v.minY + 2, 2.2, 1.4, on ? col : col.alpha(0.15))
            }
        }
        // steering wheel
        let cx = v.midX, cy = v.minY + 1
        let rot = -r.steer * 0.6
        c.cg.saveGState()
        c.cg.translateBy(x: cx, y: cy); c.cg.rotate(by: rot)
        if f1 {
            pen.rrect(CGRect(x: -11, y: -2, width: 22, height: 8), 2.5, RCol(0x1b1b1f))
            pen.rrect(CGRect(x: -5, y: 0.5, width: 10, height: 4), 0.8, RCol(0x05070a))
            c.rtext("\(Int(r.speed / 45))", 0, 0.6, 3.2, RCol.p1, .heavy, mono: true, align: .center)
            pen.circle(-8, 3.5, 0.9, RCol.red); pen.circle(8, 3.5, 0.9, RCol.go)
        } else {
            pen.arc(0, 0, 9.5, 0.15, .pi - 0.15, RCol(0x15161a), 2.6, cap: .round)
            pen.arc(0, 0, 9.5, 1.45, 1.69, accent, 2.7)
            pen.rect(-8, -0.6, 16, 2, RCol(0x1b1c20))
            pen.circle(0, 0.4, 2.6, RCol(0x24262b))
        }
        c.cg.restoreGState()
        _ = p
    }

    func drawHood(_ c: Canvas, _ r: Racer, _ v: CGRect) {
        let pen = Pen(cg: c.cg)
        let col = r.paint
        let wob = sin(CGFloat(clock) * 30) * min(1, r.speed / 6000) * 0.15
        let y0 = v.minY, top = v.minY + 8 + wob
        if r.spec.model == .f1 {
            pen.poly([(v.midX - 70, y0), (v.midX + 70, y0), (v.midX + 66, y0 + 2.4), (v.midX - 66, y0 + 2.4)], RCol(0x18181b))
            pen.poly([(v.midX - 9, y0), (v.midX + 9, y0), (v.midX + 2.5, top + 2), (v.midX - 2.5, top + 2)], col)
            pen.poly([(v.midX - 1, y0), (v.midX + 1, y0), (v.midX + 0.5, top + 2), (v.midX - 0.5, top + 2)], RCol.white.alpha(0.8))
            for s: CGFloat in [-1, 1] { pen.rrect(CGRect(x: v.midX + s * 52 - 9, y: y0 - 2, width: 18, height: 7), 2, RCol(0x141417)) }
            return
        }
        let hood = CGMutablePath()
        hood.move(to: CGPoint(x: v.midX - v.width * 0.48, y: y0))
        hood.addLine(to: CGPoint(x: v.midX - v.width * 0.36, y: top - 1.5))
        hood.addQuadCurve(to: CGPoint(x: v.midX + v.width * 0.36, y: top - 1.5), control: CGPoint(x: v.midX, y: top + 1.5))
        hood.addLine(to: CGPoint(x: v.midX + v.width * 0.48, y: y0)); hood.closeSubpath()
        pen.vgrad(CGRect(x: v.minX, y: y0, width: v.width, height: top - y0 + 1.5), [col.light(0.3), col, col.dark(0.35)], path: hood)
        c.cg.saveGState(); c.cg.addPath(hood); c.cg.clip()
        pen.vgrad(CGRect(x: v.minX, y: top - 3, width: v.width, height: 3.5), [theme.sky[1].alpha(0.55), theme.sky[2].alpha(0)])
        let sweep = (CGFloat(clock) * 25).truncatingRemainder(dividingBy: v.width * 1.6) - v.width * 0.3
        pen.poly([(v.minX + sweep, y0), (v.minX + sweep + 18, y0), (v.minX + sweep + 34, top + 2), (v.minX + sweep + 16, top + 2)], RCol.white.alpha(0.07))
        pen.polyline([CGPoint(x: v.midX - 18, y: y0), CGPoint(x: v.midX - 12, y: top - 0.6)], RCol.black.alpha(0.2), 0.6)
        pen.polyline([CGPoint(x: v.midX + 18, y: y0), CGPoint(x: v.midX + 12, y: top - 0.6)], RCol.black.alpha(0.2), 0.6)
        c.cg.restoreGState()
        pen.polyline([CGPoint(x: v.midX - v.width * 0.36, y: top - 1.5), CGPoint(x: v.midX, y: top - 0.0), CGPoint(x: v.midX + v.width * 0.36, y: top - 1.5)], RCol.white.alpha(0.4), 0.5)
    }
}
