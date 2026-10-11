import AppKit

/// Setup menu and garage.
extension RaceGame {
    func chipEntrance(_ k: Int) -> (dy: CGFloat, a: CGFloat) {
        let t = CGFloat(phaseT - 0.05 * Double(k)) / 0.45
        return ((1 - RK.easeOutBack(t)) * -14, RK.clamp(t * 2.5))
    }

    func menuBackdrop(_ c: Canvas) {
        let pen = Pen(cg: c.cg)
        let full = CGRect(x: 0, y: 0, width: width, height: 30)
        bgOffset[0] = CGFloat(clock) * 14
        drawBackground(c, 0, full, 9)
        pen.vgrad(CGRect(x: 0, y: 0, width: width, height: 10), [theme.grass.0.dark(0.2), theme.grass.0.dark(0.5)])
        pen.fill(full, RCol(0x07080c).alpha(0.62))
        pen.hgrad(CGRect(x: x0, y: 0, width: 260, height: 30), [RCol(0x07080c).alpha(0.75), RCol(0x07080c).alpha(0)])
    }

    func drawLogo(_ c: Canvas, _ x: CGFloat) -> CGFloat {
        let pen = Pen(cg: c.cg)
        for row in 0..<3 { for k in 0..<4 where (row + k) % 2 == 0 { pen.rect(x + CGFloat(k) * 3, 10.5 + CGFloat(row) * 3, 3, 3, RCol.white) } }
        pen.rect(x - 0.6, 7, 0.9, 16, RCol.white.alpha(0.7))
        let cg = c.cg
        cg.saveGState()
        cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.18, d: 1, tx: 3, ty: 0))
        c.rtext("STRIP", x + 18, 13.4, 11, RCol.white, .black)
        let w = Canvas.measure("STRIP", size: 11, weight: .black)
        c.rtext("RACER", x + 19 + w, 13.4, 11, RCol(0xff3b30), .black)
        cg.restoreGState()
        c.rtext("TOUCH BAR GRAND PRIX", x + 19, 6.2, 4.6, RCol.white.alpha(0.5), .black)
        return x + 19 + w + Canvas.measure("RACER", size: 11, weight: .black) + 8
    }

    func drawSetup(_ c: Canvas) {
        let pen = Pen(cg: c.cg)
        menuBackdrop(c)
        let logoEnd = drawLogo(c, x0 + 6)
        let widths: [CGFloat] = [96, 104, 218, 84, 128]
        let avail = width - logoEnd - 6
        let gap = (avail - widths.reduce(0, +)) / CGFloat(widths.count)
        var x = logoEnd + gap / 2
        setupRects = widths.map { w in defer { x += w + gap }; return CGRect(x: x, y: 4, width: w, height: 22) }
        // eased focus ring
        let fi = Int(floor(focusX)), ft = focusX - CGFloat(fi)
        let ra = setupRects[max(0, min(4, fi))], rb = setupRects[max(0, min(4, fi + 1))]
        let fr = CGRect(x: RK.lerp(ra.minX, rb.minX, ft), y: 4, width: RK.lerp(ra.width, rb.width, ft), height: 22).insetBy(dx: -2, dy: -2)
        pen.glow(fr.midX, fr.midY, fr.width * 0.55, RCol.white.alpha(0.08), sx: 1, sy: 0.3)
        for (k, r0) in setupRects.enumerated() {
            let e = chipEntrance(k)
            let r = r0.offsetBy(dx: 0, dy: e.dy)
            c.cg.setAlpha(e.a)
            let active = (k == 0 && !vsFriend) || (k == 1 && vsFriend) || (k == 3 && sound)
            let hue: RCol = k == 0 ? RCol.p1 : k == 1 ? RCol.p2 : k == 3 ? RCol.gold : k == 4 ? RCol.go : RCol.white
            if k == 4 {
                let pulse = 0.5 + 0.5 * sin(CGFloat(clock) * 3.2)
                pen.vgrad(r, [RCol(0x3ddc84), RCol(0x1f9d57)], path: CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
                pen.glow(r.midX, r.midY, r.width * 0.6, RCol.go.alpha(0.18 * pulse), sx: 1, sy: 0.3, add: true)
                c.rtext("START", r.minX + 12, r.minY + 5.4, 10, RCol(0x05210f), .black)
                c.rtext("▶", r.maxX - 22 + pulse * 2, r.minY + 5.6, 9, RCol(0x05210f), .black)
            } else {
                pen.rrect(r, 5, active ? hue.alpha(0.2) : RCol.white.alpha(0.06))
                pen.strokeRR(r.insetBy(dx: 0.5, dy: 0.5), 5, active ? hue.alpha(0.9) : RCol.white.alpha(0.14), active ? 1 : 0.7)
            }
            switch k {
            case 0, 1:
                let icon = k == 0 ? "1P" : "2P"
                pen.rrect(CGRect(x: r.minX + 6, y: r.midY - 5, width: 15, height: 10), 2.5, active ? hue : RCol.white.alpha(0.15))
                c.rtext(icon, r.minX + 13.5, r.midY - 3.6, 6.4, active ? RCol(0x05070a) : RCol.white.alpha(0.7), .black, align: .center)
                c.rtext(k == 0 ? "VS BOTS" : "VS FRIEND", r.minX + 26, r.minY + 9.6, 7.6, RCol.white, .heavy)
                c.rtext(k == 0 ? "\(rivals[0]) AI RIVALS" + (active ? " · TAP +" : "") : "SPLIT · \(rivals[1]) AI" + (active ? " · TAP +" : ""), r.minX + 26, r.minY + 3.6, 4.6, RCol.white.alpha(0.5), .bold)
            case 2:
                let mini = RaceTrack.preview(trackIdx)
                let mr = CGRect(x: r.maxX - 62, y: r.minY + 2.5, width: 46, height: 17)
                var w = mr.height * mini.1, h = mr.height
                if w > mr.width { w = mr.width; h = w / mini.1 }
                let o = CGPoint(x: mr.midX - w / 2, y: mr.midY - h / 2)
                let pts = mini.0.map { CGPoint(x: o.x + $0.x * w, y: o.y + $0.y * h) }
                pen.polyline(pts, RCol.white.alpha(0.25), 2.2, closed: true)
                pen.polyline(pts, RCol.white.alpha(0.85), 0.8, closed: true)
                let dotI = Int(clock * 30) % max(1, pts.count)
                if !pts.isEmpty { pen.glow(pts[dotI].x, pts[dotI].y, 3, RCol.p1, add: true); pen.circle(pts[dotI].x, pts[dotI].y, 1, RCol.white) }
                c.rtext("◀", r.minX + 6, r.minY + 6, 8, RCol.white.alpha(0.6), .black)
                c.rtext("▶", r.maxX - 12, r.minY + 6, 8, RCol.white.alpha(0.6), .black)
                c.rtext(theme.name.uppercased(), r.minX + 18, r.minY + 9.6, 8, RCol.white, .heavy)
                c.rtext("\(theme.blurb) · \(laps) LAPS", r.minX + 18, r.minY + 3.6, 4.6, RCol.white.alpha(0.5), .bold)
                for t in 0..<RaceTheme.all.count {
                    pen.circle(r.minX + 19 + CGFloat(t) * 4, r.maxY - 2.6, 0.9, t == trackIdx ? RCol.white : RCol.white.alpha(0.25))
                }
            case 3:
                let sym = sound ? "speaker.wave.2.fill" : "speaker.slash.fill"
                c.symbol(sym, in: CGRect(x: r.minX + 6, y: r.midY - 5, width: 12, height: 10), color: (sound ? RCol.gold : RCol.white.alpha(0.5)).ns, pointSize: 8)
                c.rtext("SOUND", r.minX + 22, r.minY + 9.6, 7.2, RCol.white, .heavy)
                c.rtext(sound ? "ON" : "OFF", r.minX + 22, r.minY + 3.6, 4.8, sound ? RCol.gold : RCol.white.alpha(0.5), .black)
            default: break
            }
            c.cg.setAlpha(1)
        }
        pen.strokeRR(fr, 7, RCol.white.alpha(0.85), 1.1)
    }

    // MARK: garage

    func drawGarage(_ c: Canvas) {
        let pen = Pen(cg: c.cg)
        menuBackdrop(c)
        let panels: [CGRect]
        if vsFriend {
            let mid = (x0 + width) / 2
            panels = [CGRect(x: x0, y: 1, width: mid - x0 - 9, height: 28), CGRect(x: mid + 9, y: 1, width: width - mid - 10, height: 28)]
        } else {
            panels = [CGRect(x: x0, y: 1, width: width - x0 - 1, height: 28)]
        }
        for (p, r) in panels.enumerated() { drawGaragePanel(c, p, r) }
        if vsFriend {
            let mid = (x0 + width) / 2
            pen.circle(mid, 15, 7.5, RCol(0x101218)); pen.arc(mid, 15, 7.5, 0, .pi * 2, RCol.white.alpha(0.2), 0.8)
            c.rtext("VS", mid, 11.2, 7, RCol.white, .black, align: .center)
        }
    }

    func drawGaragePanel(_ c: Canvas, _ p: Int, _ g: CGRect) {
        let pen = Pen(cg: c.cg)
        let col = accent(p)
        let e = chipEntrance(p * 2)
        c.cg.setAlpha(e.a)
        let gr = g.offsetBy(dx: 0, dy: e.dy)
        pen.rrect(gr, 5, RCol(0x0b0d12).alpha(0.85))
        pen.strokeRR(gr.insetBy(dx: 0.5, dy: 0.5), 5, col.alpha(0.35), 0.8)
        let car = RaceCar.all[carPick[p]]
        let isReady = ready[p]
        var x = gr.minX + 4
        var rects: [(String, CGRect)] = []
        func take(_ name: String, _ w: CGFloat) -> CGRect { let r = CGRect(x: x, y: gr.minY + 2, width: w, height: gr.height - 4); x += w + 4; rects.append((name, r)); return r }
        // arrows + stage
        let prev = take("prev", 12)
        c.rtext("◀", prev.midX, prev.midY - 4, 8, RCol.white.alpha(isReady ? 0.2 : 0.75), .black, align: .center)
        let stage = take("car", 82)
        let next = take("next", 12)
        c.rtext("▶", next.midX, next.midY - 4, 8, RCol.white.alpha(isReady ? 0.2 : 0.75), .black, align: .center)
        let cg = c.cg
        cg.saveGState(); cg.clip(to: stage.insetBy(dx: 0, dy: -2))
        pen.glow(stage.midX, stage.minY + 8, 40, col.alpha(0.18), sx: 1, sy: 0.5)
        pen.glow(stage.midX, stage.maxY + 6, 30, RCol.white.alpha(0.12), sx: 1, sy: 0.6)
        let ty = stage.minY + 2.2
        pen.ellipse(CGRect(x: stage.midX - 34, y: ty - 3, width: 68, height: 6), RCol(0x161922))
        pen.arc(stage.midX, ty, 34, 0, .pi * 2, col.alpha(0.0), 0.1)
        for k in 0..<12 {
            let a = CGFloat(k) / 12 * 2 * .pi + CGFloat(clock) * 0.8
            guard sin(a) < 0.2 else { continue }
            pen.circle(stage.midX + cos(a) * 31, ty + sin(a) * 2.4, 0.55, col.alpha(0.5 + 0.5 * -sin(a)))
        }
        let since = CGFloat(clock - carChangedAt[p])
        let slide = (1 - RK.easeOutBack(since / 0.45)) * 50
        let bob = sin(CGFloat(clock) * 2.2 + CGFloat(p)) * 0.5
        let cw = min(64, 23.5 / car.aspect)
        let yaw = 0.93 + 0.07 * cos(CGFloat(clock) * 1.1)
        cg.saveGState()
        cg.translateBy(x: stage.midX + slide, y: 0); cg.scaleBy(x: yaw, y: 1); cg.translateBy(x: -(stage.midX + slide), y: 0)
        let sweep = (CGFloat(clock * 0.55).truncatingRemainder(dividingBy: 2.6)) - 1.3
        let pose = CarPose(steer: sin(CGFloat(clock) * 1.1) * 0.55, brake: sin(clock * 1.3) > 0.55, boost: isReady && Int(clock * 3) % 4 != 0,
                           wheel: CGFloat(clock) * 3, wing: isReady ? 1 : 0.5 + 0.5 * sin(CGFloat(clock) * 0.8), time: clock, night: false, sheen: sweep, seed: p)
        CarArt.draw(c, car, cx: stage.midX + slide, by: ty + bob * 0.3, w: cw, pose: pose)
        cg.restoreGState()
        cg.restoreGState()
        // info
        let info = take("info", 98)
        c.rtext(car.maker, info.minX, info.minY + 17.4, 4.8, col, .black)
        c.rtext(car.name.uppercased(), info.minX, info.minY + 6.2, 10.5, RCol.white, .heavy, maxWidth: info.width)
        c.rtext(car.tag, info.minX, info.minY + 0.6, 4.4, RCol.white.alpha(0.5), .bold, maxWidth: info.width)
        // stats
        let st = take("stats", vsFriend ? 92 : 132)
        let stats: [(String, CGFloat)] = [("SPEED", (car.top - 9000) / 4600), ("ACCEL", (car.accel - 4600) / 4600), ("GRIP", (car.handling - 1.8) / 1.4), ("4X4", (car.offroad - 0.28) / 0.66)]
        for (k, s) in stats.enumerated() {
            let y = st.maxY - 5.6 - CGFloat(k) * 6
            c.rtext(s.0, st.minX, y - 0.6, 4.2, RCol.white.alpha(0.5), .black)
            let bx = st.minX + 18, bw = st.width - 18
            let v = (0.12 + 0.88 * RK.clamp(s.1)) * RK.easeOut((since - CGFloat(k) * 0.06) / 0.6)
            pen.rrect(CGRect(x: bx, y: y, width: bw, height: 2.4), 1.2, RCol.white.alpha(0.08))
            pen.hgrad(CGRect(x: bx, y: y, width: bw * v, height: 2.4), [col.dark(0.3), col])
            pen.circle(bx + bw * v, y + 1.2, 1.3, RCol.white.alpha(0.9))
        }
        // camera view
        let pv = take("pov", 56)
        pen.rrect(pv, 4, RCol.white.alpha(0.06)); pen.strokeRR(pv.insetBy(dx: 0.5, dy: 0.5), 4, RCol.white.alpha(0.14), 0.7)
        c.rtext("CAMERA  W/S", pv.midX, pv.minY + 14.5, 4.2, RCol.white.alpha(0.5), .black, align: .center)
        c.rtext(Self.povNames[pov[p]], pv.midX, pv.minY + 4.6, 8, RCol.white, .heavy, align: .center)
        for k in 0..<3 { pen.circle(pv.midX - 4 + CGFloat(k) * 4, pv.minY + 2.6, 0.9, k == pov[p] ? col : RCol.white.alpha(0.25)) }
        if !vsFriend {
            let ai = take("ai", 56)
            pen.rrect(ai, 4, RCol.white.alpha(0.06)); pen.strokeRR(ai.insetBy(dx: 0.5, dy: 0.5), 4, RCol.white.alpha(0.14), 0.7)
            c.rtext("BOTS  G", ai.midX, ai.minY + 14.5, 4.2, RCol.white.alpha(0.5), .black, align: .center)
            c.rtext(Self.difficulties[difficulty], ai.midX, ai.minY + 4.6, 8, [RCol.go, RCol.gold, RCol.red][difficulty], .heavy, align: .center)
        }
        // ready
        let rdW = max(60, gr.maxX - 4 - x)
        let rd = CGRect(x: x, y: gr.minY + 2, width: rdW, height: gr.height - 4)
        rects.append(("ready", rd))
        if isReady {
            let pulse = 0.5 + 0.5 * sin(CGFloat(clock) * 5)
            pen.rrect(rd, 4, col.alpha(0.8 + 0.2 * pulse))
            c.rtext("READY ✓", rd.midX, rd.minY + 7.4, 8.4, RCol(0x05070a), .black, align: .center)
            if vsFriend { c.rtext("WAITING…", rd.midX, rd.minY + 1.8, 4.2, RCol(0x05070a).alpha(0.7), .black, align: .center) }
        } else {
            pen.rrect(rd, 4, col.alpha(0.12)); pen.strokeRR(rd.insetBy(dx: 0.5, dy: 0.5), 4, col.alpha(0.8), 0.9)
            c.rtext("READY", rd.midX, rd.minY + 8.4, 8.4, RCol.white, .heavy, align: .center)
            c.rtext(p == 0 ? "PRESS F" : "PRESS /", rd.midX, rd.minY + 2.4, 4.4, col, .black, align: .center)
        }
        garageRects[p] = rects
        c.cg.setAlpha(1)
    }
}
