import AppKit

/// Speedometer clusters, minimap, leaderboard, start lights, toasts, results and confetti.
extension RaceGame {
    func accent(_ p: Int) -> RCol { p == 0 ? RCol.p1 : RCol.p2 }

    func panel(_ pen: Pen, _ r: CGRect, _ glow: RCol? = nil) {
        pen.cg.saveGState()
        let path = CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil)
        pen.vgrad(r, [RCol(0x1c2029), RCol(0x0e1015)], path: path)
        pen.cg.restoreGState()
        if let glow { pen.vgrad(CGRect(x: r.minX, y: r.maxY - 6, width: r.width, height: 6), [glow.alpha(0.16), glow.alpha(0)], path: path) }
        pen.strokeRR(r.insetBy(dx: 0.5, dy: 0.5), 4, RCol.white.alpha(0.08), 1)
    }

    // MARK: gauge

    func drawGauge(_ c: Canvas, _ p: Int, _ g: CGRect) {
        let pen = Pen(cg: c.cg)
        let r = racers[humanIdx[p]]
        let col = accent(p)
        panel(pen, g, col)
        let pct = RK.clamp(r.speed / (r.spec.top * 1.22))
        let cx = g.minX + 16, cy = g.midY, R: CGFloat = 12.6
        let a0: CGFloat = .pi * 1.25, a1: CGFloat = -.pi * 0.25
        func ang(_ t: CGFloat) -> CGFloat { a0 + (a1 - a0) * t }
        pen.circle(cx, cy, R + 0.6, RCol(0x07080b))
        pen.arc(cx, cy, R - 1, a0, a1, RCol(0x2a2f3a), 1.6)
        pen.arc(cx, cy, R - 1, ang(0.82), a1, RCol.red.alpha(0.75), 1.6)
        pen.arc(cx, cy, R - 1, a0, ang(pct), col, 1.6)
        for k in 0...10 {
            let t = CGFloat(k) / 10, a = ang(t)
            let inner = R - (k % 2 == 0 ? 4.2 : 3.2)
            pen.line(CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner), CGPoint(x: cx + cos(a) * (R - 2.2), y: cy + sin(a) * (R - 2.2)),
                     t >= 0.8 ? RCol.red : RCol.white.alpha(0.7), k % 2 == 0 ? 0.7 : 0.4)
        }
        let jitter = r.speed > 300 ? sin(CGFloat(clock) * 40) * 0.006 : 0
        let na = ang(pct + jitter)
        pen.glow(cx + cos(na) * 6, cy + sin(na) * 6, 5, RCol(0xff4b3a).alpha(0.35), add: true)
        pen.line(CGPoint(x: cx - cos(na) * 2, y: cy - sin(na) * 2), CGPoint(x: cx + cos(na) * (R - 2.6), y: cy + sin(na) * (R - 2.6)), RCol(0xff5a46), 1, round: true)
        pen.circle(cx, cy, 1.9, RCol(0x2a2d35)); pen.circle(cx, cy, 0.9, RCol(0xd0d4dc))
        c.rtext("P\(p + 1)", cx, cy - 10.5, 4.6, col, .black, align: .center)

        let kmh = Int(r.speed / 45)
        let sx = g.minX + 34
        c.rtext(String(format: "%03d", kmh), sx, 10.2, 15, RCol.white, .heavy, mono: true)
        c.rtext("KM/H", sx + 1, 24.2, 4.6, RCol.white.alpha(0.45), .bold)
        // nitro
        let bx = sx, bw = g.maxX - 24 - bx
        let segs = 10
        let flick = r.boosting ? 0.75 + 0.25 * sin(CGFloat(clock) * 50) : 1
        for k in 0..<segs {
            let x = bx + CGFloat(k) * bw / CGFloat(segs)
            let on = CGFloat(k) / CGFloat(segs) < r.nitro - 0.02
            let cc = RCol(0x31c6ff).mix(RCol(0x7a5cff), CGFloat(k) / CGFloat(segs))
            pen.rrect(CGRect(x: x, y: 3.2, width: bw / CGFloat(segs) - 1, height: 3.2), 0.8, on ? cc.alpha(flick) : RCol.white.alpha(0.08))
        }
        if r.boosting { pen.glow(bx + bw * r.nitro, 4.8, 10, RCol(0x31c6ff).alpha(0.5), sx: 1.4, sy: 0.5, add: true) }
        c.rtext("N₂O", bx, 7.2, 4.4, RCol(0x7fd8ff).alpha(0.75), .black)
        // gear
        let gb = CGRect(x: g.maxX - 21, y: 3.2, width: 17, height: 19.5)
        pen.rrect(gb, 3, RCol(0x07080b))
        pen.strokeRR(gb.insetBy(dx: 0.4, dy: 0.4), 3, col.alpha(0.35), 0.8)
        let gear = r.speed < 120 ? "N" : "\(min(7, 1 + Int(r.speed / r.spec.top * 6.5)))"
        c.rtext(gear, gb.midX, gb.minY + 3, 12.5, col, .heavy, mono: true, align: .center)
        c.rtext("GEAR", gb.midX, gb.maxY + 0.6, 4.2, RCol.white.alpha(0.45), .bold, align: .center)
    }

    // MARK: minimap

    func drawMinimap(_ c: Canvas, _ m: CGRect) {
        let pen = Pen(cg: c.cg)
        panel(pen, m)
        let side: CGFloat = 40
        let area = CGRect(x: m.minX + side, y: m.minY + 3, width: m.width - side * 2, height: m.height - 6)
        var w = area.height * track.mapAspect, h = area.height
        if w > area.width { w = area.width; h = w / track.mapAspect }
        let o = CGPoint(x: area.midX - w / 2, y: area.midY - h / 2)
        func pt(_ q: CGPoint) -> CGPoint { CGPoint(x: o.x + q.x * w, y: o.y + q.y * h) }
        var pts: [CGPoint] = []
        for i in stride(from: 0, to: track.map.count, by: 3) { pts.append(pt(track.map[i])) }
        pen.polyline(pts, RCol.black.alpha(0.6), 3.6, closed: true)
        pen.polyline(pts, RCol(0x5a6272), 2, closed: true)
        pen.polyline(pts, RCol(0x8a93a5).alpha(0.6), 0.6, closed: true)
        let s0 = pt(track.mapPoint(0)), s1 = pt(track.mapPoint(RaceTrack.segLen * 3))
        let dir = CGPoint(x: s1.x - s0.x, y: s1.y - s0.y), len = max(0.01, hypot(dir.x, dir.y))
        let nrm = CGPoint(x: -dir.y / len * 2.4, y: dir.x / len * 2.4)
        pen.line(CGPoint(x: s0.x - nrm.x, y: s0.y - nrm.y), CGPoint(x: s0.x + nrm.x, y: s0.y + nrm.y), RCol.white, 1)
        let order = racers.indices.sorted { (racers[$0].human ?? -1) < (racers[$1].human ?? -1) }
        for i in order {
            let q = pt(track.mapPoint(racers[i].d))
            if let hp = racers[i].human {
                let col = accent(hp)
                let pulse = 1 + 0.25 * sin(CGFloat(clock) * 6 + CGFloat(hp) * 2)
                pen.glow(q.x, q.y, 5 * pulse, col.alpha(0.55), add: true)
                pen.circle(q.x, q.y, 2.1, RCol.white); pen.circle(q.x, q.y, 1.5, col)
            } else {
                pen.circle(q.x, q.y, 1.5, RCol.black.alpha(0.6)); pen.circle(q.x, q.y, 1.1, RCol(0xb4b9c3))
            }
        }
        let rank = ranking()
        func info(_ hp: Int, _ x: CGFloat, _ align: NSTextAlignment) {
            guard hp < humanIdx.count else { return }
            let r = racers[humanIdx[hp]]
            let pos = (rank.firstIndex(of: humanIdx[hp]) ?? 0) + 1
            c.rtext(RK.ordinal(pos).uppercased(), x, 11.5, 10, accent(hp), .heavy, align: align)
            c.rtext("LAP \(min(laps, r.lap + 1))/\(laps)", x, 4, 5.6, RCol.white.alpha(0.75), .bold, align: align)
            c.rtext("P\(hp + 1)", x, 22, 4.8, accent(hp).alpha(0.7), .black, align: align)
        }
        info(0, m.minX + 6, .left)
        if vsFriend {
            info(1, m.maxX - 6, .right)
        } else {
            c.rtext(RK.time(raceTime), m.maxX - 6, 11.8, 7.4, RCol.white, .bold, mono: true, align: .right)
            let best = humanIdx.first.flatMap { racers[$0].bestLap }
            c.rtext(best.map { "BEST \(RK.time($0))" } ?? theme.name.uppercased(), m.maxX - 6, 4, 4.8, RCol.white.alpha(0.55), .bold, align: .right)
            c.rtext("TIME", m.maxX - 6, 22, 4.8, RCol.white.alpha(0.45), .black, align: .right)
        }
    }

    // MARK: leaderboard

    func drawBoard(_ c: Canvas, _ b: CGRect) {
        let pen = Pen(cg: c.cg)
        panel(pen, b)
        let rank = ranking()
        let head: CGFloat = 30
        c.rtext("LIVE", b.minX + head / 2 + 2, 17.5, 5, RCol.red, .black, align: .center)
        pen.circle(b.minX + 6, 20.4, 1.1, RCol.red.alpha(0.6 + 0.4 * CGFloat(sin(clock * 5))))
        c.rtext("\(laps)L", b.minX + head / 2 + 2, 6, 8, RCol.white.alpha(0.6), .heavy, align: .center)
        let n = CGFloat(racers.count)
        let cw = (b.width - head - 4) / n
        let leader = racers[rank[0]]
        for (pos, i) in rank.enumerated() {
            let target = CGFloat(pos)
            let cur = boardOrder[i] ?? target
            let nx = RK.approach(cur, target, 9, 1.0 / 60)
            boardOrder[i] = nx
            let o = racers[i]
            let r = CGRect(x: b.minX + head + nx * cw + 1, y: 3, width: cw - 3, height: 24)
            let mine = o.human != nil
            let col = o.human.map { accent($0) } ?? RCol(0xb4b9c3)
            pen.rrect(r, 3, mine ? col.alpha(0.16) : RCol.white.alpha(0.04))
            if mine { pen.strokeRR(r.insetBy(dx: 0.5, dy: 0.5), 3, col.alpha(0.7), 0.8) }
            c.rtext("\(pos + 1)", r.minX + 4, 9.5, 11, pos == 0 ? RCol.gold : RCol.white.alpha(0.85), .heavy, mono: true)
            pen.rrect(CGRect(x: r.minX + 13, y: 6, width: 1.6, height: 18), 0.8, o.paint)
            c.rtext(o.name, r.minX + 17, 15, 6.6, mine ? col : RCol.white, .heavy, maxWidth: r.width - 19)
            let gap: String
            if pos == 0 { gap = o.finished != nil ? "FINISHED" : "LEADER" } else if let f = o.finished, let lf = leader.finished { gap = String(format: "+%.1fs", f - lf) } else {
                gap = String(format: "+%.1fs", Double((leader.d - o.d) / max(o.speed, 3000)))
            }
            c.rtext(gap, r.minX + 17, 6.5, 5, RCol.white.alpha(0.55), .bold, mono: true, maxWidth: r.width - 19)
        }
    }

    // MARK: in-view overlays

    func drawViewOverlay(_ c: Canvas, _ p: Int, _ v: CGRect) {
        let pen = Pen(cg: c.cg)
        let col = accent(p)
        // start lights pod
        let lit = phase == .countdown ? min(5, Int(countT / 0.6)) : 0
        let goT = phase == .race ? raceTime : -1
        let podIn = phase == .countdown ? RK.easeOutBack(CGFloat(countT) / 0.45) : RK.clamp(1 - CGFloat(goT - 0.7) / 0.35)
        if podIn > 0.01 {
            let pw: CGFloat = 52, ph: CGFloat = 10
            let py = v.maxY - ph - 2 + (1 - podIn) * 14
            let pr = CGRect(x: v.midX - pw / 2, y: py, width: pw, height: ph)
            pen.rrect(pr.insetBy(dx: -1, dy: -1), 3.5, RCol.black.alpha(0.35))
            pen.rrect(pr, 3, RCol(0x101114))
            for k in 0..<5 {
                let lx = pr.minX + 6 + CGFloat(k) * 10, ly = pr.midY
                let on = k < lit, green = goT >= 0
                pen.circle(lx, ly, 3.3, RCol(0x050506))
                let cc = green ? RCol(0x3ddc84) : on ? RCol(0xff2a1a) : RCol(0x3a1612)
                pen.circle(lx, ly, 2.7, cc)
                if on || green { pen.glow(lx, ly, 7, cc.alpha(0.55), add: true); pen.circle(lx - 0.8, ly + 0.8, 0.8, RCol.white.alpha(0.6)) }
            }
        }
        if goT >= 0, goT < 1.1 {
            let t = CGFloat(goT)
            let sc = RK.easeOutBack(t / 0.3)
            let a = RK.clamp((1.1 - t) / 0.4)
            c.rtext("GO!", v.midX, v.midY - 9 * sc + 1, 18 * sc, RCol.go.alpha(a), .black, align: .center)
        }
        if phase == .countdown, lit == 0 {
            c.rtext(theme.name.uppercased(), v.midX, 4, 6, RCol.white.alpha(0.85), .black, align: .center)
        }
        // lap / finish toast
        if let (msg, at) = lapToast[p] {
            let age = CGFloat(clock - at)
            let finished = humanIdx.count > p && racers[humanIdx[p]].finished != nil
            let life: CGFloat = finished ? 99 : 2.2
            if age < life {
                let inT = RK.easeOutBack(age / 0.35), out = RK.clamp((life - age) / 0.3)
                let tw = Canvas.measure(msg, size: 6.4, weight: .heavy) + 14
                let r = CGRect(x: v.midX - tw / 2, y: v.minY + 3 - (1 - inT) * 12, width: tw, height: 10)
                c.cg.setAlpha(out)
                pen.rrect(r, 5, RCol.black.alpha(0.65)); pen.strokeRR(r.insetBy(dx: 0.5, dy: 0.5), 5, col.alpha(0.8), 0.8)
                c.rtext(msg, r.midX, r.minY + 1.6, 6.4, RCol.white, .heavy, align: .center)
                c.cg.setAlpha(1)
            }
        }
        // corner tags
        let tag = "P\(p + 1)  \(Self.povNames[pov[p]])"
        let tw = Canvas.measure(tag, size: 4.6, weight: .black) + 6
        pen.rrect(CGRect(x: v.minX + 3, y: v.maxY - 8, width: tw, height: 6), 2, RCol.black.alpha(0.45))
        c.rtext(tag, v.minX + 6, v.maxY - 7.6, 4.6, col, .black)
    }

    // MARK: particles, results, transitions

    func drawParticles(_ c: Canvas, _ view: Int, _ rect: CGRect) {
        let pen = Pen(cg: c.cg)
        for q in particles where q.view == view {
            let x = rect.minX + q.x * rect.width, y = rect.minY + q.y * rect.height
            let w: CGFloat = 1.8, h = 1.1 * abs(cos(q.rot))
            let ca = cos(q.rot * 0.7), sa = sin(q.rot * 0.7)
            let pts = [(-w, -h), (w, -h), (w, h), (-w, h)].map { CGPoint(x: x + ($0.0 * ca - $0.1 * sa) / 2, y: y + ($0.0 * sa + $0.1 * ca) / 2) }
            pen.poly(pts, q.col.alpha(RK.clamp(q.life)))
        }
    }

    func drawResults(_ c: Canvas) {
        let pen = Pen(cg: c.cg)
        let t = RK.easeOut(CGFloat(phaseT) / 0.5)
        pen.fill(c.bounds, RCol.black.alpha(0.72 * t))
        let rank = ranking()
        let left = x0 + 4
        let slide = (1 - t) * 30
        let winner = racers[rank[0]]
        let title = winner.human.map { vsFriend ? "P\($0 + 1) WINS" : "VICTORY" } ?? (humanIdx.first.map { "P\(((rank.firstIndex(of: $0) ?? 0) + 1))" } != nil ? "\(RK.ordinal((rank.firstIndex(of: humanIdx[0]) ?? 0) + 1).uppercased()) PLACE" : "RESULTS")
        let tcol = winner.human.map { accent($0) } ?? RCol.white
        c.cg.setAlpha(t)
        c.rtext("RESULTS · \(theme.name.uppercased())", left, 20, 5.4, RCol.white.alpha(0.55), .black)
        c.rtext(title, left - slide, 5, 14, tcol, .heavy)
        let startX = left + 112
        let rw = (width - startX - 92) / CGFloat(rank.count)
        for (pos, i) in rank.enumerated() {
            let o = racers[i]
            let delay = 0.15 + Double(pos) * 0.07
            let k = RK.easeOutBack(CGFloat(phaseT - delay) / 0.4)
            guard k > 0 else { continue }
            let r = CGRect(x: startX + CGFloat(pos) * rw, y: 3 - (1 - k) * 10, width: rw - 4, height: 24)
            let col = o.human.map { accent($0) } ?? RCol(0x9aa0aa)
            pen.rrect(r, 4, (pos == 0 ? RCol.gold : col).alpha(o.human != nil || pos == 0 ? 0.16 : 0.06))
            pen.strokeRR(r.insetBy(dx: 0.5, dy: 0.5), 4, (pos == 0 ? RCol.gold : col).alpha(o.human != nil ? 0.8 : 0.25), 0.8)
            c.rtext("\(pos + 1)", r.minX + 5, 8, 13, pos == 0 ? RCol.gold : RCol.white, .heavy, mono: true)
            CarArt.draw(c, o.spec, paint: o.paint, cx: r.minX + 26, by: r.minY + 3, w: min(18, 15 / o.spec.aspect))
            c.rtext(o.name, r.minX + 38, 14.5, 7, o.human != nil ? col : RCol.white, .heavy, maxWidth: r.width - 40)
            c.rtext(o.finished.map { RK.time($0) } ?? "DNF", r.minX + 38, 6.5, 5.6, RCol.white.alpha(0.7), .bold, mono: true)
        }
        let blink = 0.55 + 0.45 * sin(CGFloat(phaseT) * 4)
        let br = CGRect(x: width - 86, y: 6, width: 82, height: 18)
        pen.rrect(br, 9, RCol.go.alpha(0.18 + 0.12 * blink)); pen.strokeRR(br.insetBy(dx: 0.5, dy: 0.5), 9, RCol.go.alpha(0.8), 0.8)
        c.rtext("REMATCH  ●", br.midX, br.minY + 4.6, 7, RCol.white, .heavy, align: .center)
        c.cg.setAlpha(1)
    }

    func drawWipe(_ c: Canvas) {
        let t = CGFloat(phaseT) / 0.35
        guard t < 1, phase != .results else { return }
        let pen = Pen(cg: c.cg)
        let a = 1 - RK.easeOut(t)
        let r = CGRect(x: x0 - 2, y: 0, width: width - x0 + 2, height: 30)
        pen.fill(r, RCol(0x07080c).alpha(a * 0.85))
        let sweep = r.minX + r.width * RK.easeInOut(t)
        pen.hgrad(CGRect(x: sweep - 60, y: 0, width: 60, height: 30), [RCol.white.alpha(0), RCol.white.alpha(0.12 * a)])
    }
}
