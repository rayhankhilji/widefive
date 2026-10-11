import AppKit

struct RaceCar {
    enum Model { case lambo, f1, defender, gwagon, m5, r8, laferrari }
    let name: String, maker: String, tag: String
    let model: Model
    let top: CGFloat, accel: CGFloat, handling: CGFloat, offroad: CGFloat
    let paints: [RCol]
    /// Rear-view height / width.
    let aspect: CGFloat
    var kmh: Int { Int(top / 45) }
    var color: RCol { paints[0] }

    static let all: [RaceCar] = [
        RaceCar(name: "Aventador", maker: "LAMBORGHINI", tag: "V12 · AWD", model: .lambo, top: 12800, accel: 7400, handling: 2.5, offroad: 0.42,
                paints: [RCol(0x8fd11b), RCol(0xff8a00), RCol(0xf5d000), RCol(0x6b2bd9)], aspect: 0.5),
        RaceCar(name: "F1", maker: "FORMULA", tag: "1.6 V6 HYBRID", model: .f1, top: 13600, accel: 9200, handling: 3.2, offroad: 0.3,
                paints: [RCol(0xe10600), RCol(0x00a19c), RCol(0xff8000), RCol(0x1e41ff)], aspect: 0.5),
        RaceCar(name: "Defender", maker: "LAND ROVER", tag: "4X4 · DIFF LOCK", model: .defender, top: 9400, accel: 4800, handling: 2.0, offroad: 0.92,
                paints: [RCol(0x3d5a40), RCol(0x9b8f6d), RCol(0x2b4a6b), RCol(0x6b2a24)], aspect: 0.9),
        RaceCar(name: "G 63", maker: "MERCEDES", tag: "V8 BITURBO · 4MATIC", model: .gwagon, top: 9800, accel: 5300, handling: 1.9, offroad: 0.85,
                paints: [RCol(0x1f2024), RCol(0xe8e8e6), RCol(0x5c6168), RCol(0x6e5a3e)], aspect: 0.92),
        RaceCar(name: "M5", maker: "BMW", tag: "V8 · M xDRIVE", model: .m5, top: 11500, accel: 6600, handling: 2.4, offroad: 0.5,
                paints: [RCol(0x1f5fd0), RCol(0x2c2c30), RCol(0xd8dde2), RCol(0x7a1f2b)], aspect: 0.66),
        RaceCar(name: "R8", maker: "AUDI", tag: "V10 · QUATTRO", model: .r8, top: 12200, accel: 7000, handling: 2.7, offroad: 0.45,
                paints: [RCol(0xbfc4cb), RCol(0xf2f2f0), RCol(0x1d3f8f), RCol(0xd23a1e)], aspect: 0.54),
        RaceCar(name: "LaFerrari", maker: "FERRARI", tag: "V12 HY-KERS", model: .laferrari, top: 13100, accel: 7800, handling: 2.6, offroad: 0.4,
                paints: [RCol(0xd40000), RCol(0xffd400), RCol(0x111114), RCol(0xf4f4f4)], aspect: 0.47),
    ]
}

enum RaceScene { case gp, coast, alpine, night }

struct RaceTheme {
    let name: String, blurb: String
    let scene: RaceScene
    let sky: [RCol]                 // top → horizon
    let grass: (RCol, RCol), road: (RCol, RCol), runoff: RCol, kerb: (RCol, RCol)
    let line: RCol, edge: RCol, fog: RCol
    let points: [(CGFloat, CGFloat)]
    let elevation: [(CGFloat, CGFloat)]
    var night: Bool { scene == .night }

    static let all: [RaceTheme] = [
        RaceTheme(name: "Grand Prix", blurb: "F1 CIRCUIT", scene: .gp,
                  sky: [RCol(0x2f7fe0), RCol(0x7db8f2), RCol(0xd8ecff)],
                  grass: (RCol(0x3f9a3a), RCol(0x388f34)), road: (RCol(0x55575e), RCol(0x515359)), runoff: RCol(0xd9c28c),
                  kerb: (RCol(0xe0221c), RCol(0xf4f4f4)), line: RCol(0xffffff), edge: RCol(0xffffff), fog: RCol(0xc9def2),
                  points: [(30, 2), (62, 2), (80, 2.5), (88, 5), (88, 9), (83, 11.5), (86, 14.5), (93, 17), (93, 21), (86, 23), (72, 22.5),
                           (64, 18.5), (55, 19.5), (44, 22.5), (28, 22.5), (19, 21.5), (16, 17), (22, 13.5), (17, 10), (6, 9.5), (2.5, 6), (6, 2.5)],
                  elevation: [(0, 0), (0.18, 300), (0.35, -200), (0.55, 700), (0.75, 200), (0.9, -100), (1, 0)]),
        RaceTheme(name: "Coast", blurb: "SEASIDE ROAD", scene: .coast,
                  sky: [RCol(0x3a8ee6), RCol(0x8cc6f5), RCol(0xffe2b8)],
                  grass: (RCol(0xe6d39a), RCol(0xdcc88c)), road: (RCol(0x5d5d66), RCol(0x595962)), runoff: RCol(0xcdbb84),
                  kerb: (RCol(0xffffff), RCol(0xd8302b)), line: RCol(0xf6f6f0), edge: RCol(0xffffff), fog: RCol(0xd6e9f7),
                  points: [(8, 3), (26, 2), (40, 4), (55, 2.5), (75, 3), (90, 2), (97, 5.5), (96, 10), (88, 12), (80, 16), (70, 18), (61, 15),
                           (51, 17), (41, 13.5), (31, 16), (21, 18.5), (9, 17.5), (2.5, 13), (2.5, 6.5)],
                  elevation: [(0, 0), (0.12, 500), (0.3, -150), (0.5, 900), (0.62, 1500), (0.78, 600), (0.92, 200), (1, 0)]),
        RaceTheme(name: "Alpine", blurb: "MOUNTAIN PASS", scene: .alpine,
                  sky: [RCol(0x3b6fc4), RCol(0x8fb6e8), RCol(0xeaf3ff)],
                  grass: (RCol(0xf4f7fb), RCol(0xe6edf5)), road: (RCol(0x4c4d55), RCol(0x484951)), runoff: RCol(0xdfe6ef),
                  kerb: (RCol(0xd8302b), RCol(0xffffff)), line: RCol(0xffcf33), edge: RCol(0xf0f0f0), fog: RCol(0xe9f1fb),
                  points: [(10, 2), (40, 2), (68, 3), (88, 2), (96, 5), (92, 8.5), (80, 8.5), (78, 11.5), (92, 12.5), (95, 16), (83, 17), (79, 20),
                           (90, 22), (86, 24.5), (66, 23), (46, 24), (28, 21), (12, 22.5), (3, 18), (7, 12), (3, 7.5), (4, 3.5)],
                  elevation: [(0, 0), (0.15, 400), (0.25, 1400), (0.33, 2600), (0.42, 3800), (0.5, 4200), (0.62, 3200), (0.78, 1600), (0.9, 500), (1, 0)]),
        RaceTheme(name: "Night City", blurb: "STREET CIRCUIT", scene: .night,
                  sky: [RCol(0x05060f), RCol(0x0e1430), RCol(0x2a2346)],
                  grass: (RCol(0x24262e), RCol(0x22242b)), road: (RCol(0x2c2e36), RCol(0x2a2c33)), runoff: RCol(0x34363e),
                  kerb: (RCol(0xd8302b), RCol(0xe8e8e8)), line: RCol(0xf3f3f3), edge: RCol(0xd9d9d9), fog: RCol(0x1b1d33),
                  points: [(10, 3), (55, 3), (59, 5), (59, 9), (63, 11), (90, 11), (95, 13), (95, 18.5), (91, 21), (42, 21), (37, 19),
                           (37, 15.5), (33, 13.5), (9, 13.5), (4, 11), (4, 5.5)],
                  elevation: [(0, 0), (0.2, 150), (0.4, -100), (0.55, 600), (0.62, 600), (0.75, 0), (1, 0)]),
    ]
}

struct RaceWall {
    enum Kind { case pit, armco, stand, rock, snow, building, fence, seawall, garage }
    let kind: Kind
    let x: CGFloat       // lateral offset in road half-widths (positive)
    let h: CGFloat       // height in world units
}

struct RaceProp {
    enum Kind { case tree, palm, pine, rock, tyres, board, gantry, marshal, pole, lamp, chalet, hut, lighthouse, chevron, bush, banner }
    let kind: Kind
    let x: CGFloat       // signed lateral offset in road half-widths
    let v: CGFloat       // variant 0..1
}

struct RaceSeg {
    var curve: CGFloat
    var y1: CGFloat, y2: CGFloat
    var kerb = false
    var runoff: CGFloat = 1.25
    var wallL: RaceWall?, wallR: RaceWall?
    var props: [RaceProp] = []
}

/// A closed circuit: segment curves are derived from a smoothed waypoint loop, so the minimap
/// (re-integrated from those curves) is exactly the road you drive.
final class RaceTrack {
    static let segLen: CGFloat = 200
    static let curveK: CGFloat = 30
    let theme: RaceTheme
    private(set) var segs: [RaceSeg] = []
    private(set) var map: [CGPoint] = []       // normalised 0…1 in both axes
    private(set) var mapAspect: CGFloat = 4
    var count: Int { segs.count }
    var length: CGFloat { CGFloat(segs.count) * Self.segLen }

    init(_ theme: RaceTheme, segments: Int = 1150) {
        self.theme = theme
        build(segments)
    }

    func wrap(_ d: CGFloat) -> CGFloat {
        let m = d.truncatingRemainder(dividingBy: length)
        return m < 0 ? m + length : m
    }
    func index(_ d: CGFloat) -> Int { Int(wrap(d) / Self.segLen) % segs.count }
    func seg(_ d: CGFloat) -> RaceSeg { segs[index(d)] }
    func height(_ d: CGFloat) -> CGFloat {
        let z = wrap(d)
        let i = Int(z / Self.segLen) % segs.count
        let t = (z - CGFloat(i) * Self.segLen) / Self.segLen
        return segs[i].y1 + (segs[i].y2 - segs[i].y1) * t
    }
    func mapPoint(_ d: CGFloat) -> CGPoint {
        let z = wrap(d) / Self.segLen
        let i = Int(z) % map.count, j = (i + 1) % map.count, t = z - CGFloat(Int(z))
        return CGPoint(x: map[i].x + (map[j].x - map[i].x) * t, y: map[i].y + (map[j].y - map[i].y) * t)
    }

    private static var previews: [Int: ([CGPoint], CGFloat)] = [:]
    /// Low-res minimap outline for menus (cached per track).
    static func preview(_ i: Int) -> ([CGPoint], CGFloat) {
        if let p = previews[i] { return p }
        let t = RaceTrack(RaceTheme.all[i])
        let p = (stride(from: 0, to: t.map.count, by: 8).map { t.map[$0] }, t.mapAspect)
        previews[i] = p
        return p
    }

    // MARK: build

    private func build(_ n: Int) {
        let pts = Self.spline(theme.points, samples: n)
        var dtheta = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n], c = pts[(i + 2) % n]
            var d = atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x)
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            dtheta[i] = d
        }
        // light smoothing so corners ease in/out
        var smooth = dtheta
        for i in 0..<n {
            var sum: CGFloat = 0
            for k in -2...2 { sum += dtheta[(i + k + n) % n] }
            smooth[i] = sum / 5
        }
        let curves = smooth.map { max(-3, min(3, -$0 * Self.curveK)) }

        func elev(_ f: CGFloat) -> CGFloat {
            let e = theme.elevation
            for k in 0..<(e.count - 1) where f >= e[k].0 && f <= e[k + 1].0 {
                let t = (f - e[k].0) / max(0.0001, e[k + 1].0 - e[k].0)
                return e[k].1 + (e[k + 1].1 - e[k].1) * (1 - cos(t * .pi)) / 2
            }
            return 0
        }
        segs = (0..<n).map { i in
            RaceSeg(curve: curves[i], y1: elev(CGFloat(i) / CGFloat(n)), y2: elev(CGFloat(i + 1) / CGFloat(n)))
        }
        // kerbs + run-off on corners (with a little lead-in / lead-out)
        for i in 0..<n {
            let near = (-8...8).contains { abs(segs[(i + $0 + n) % n].curve) > 0.55 }
            segs[i].kerb = near
            segs[i].runoff = near ? (theme.scene == .gp ? 2.6 : 1.45) : (theme.scene == .gp ? 1.7 : 1.25)
        }
        buildMap(curves)
        decorate()
    }

    /// Re-integrates the segment curves into the minimap outline (tiny closure error spread over the lap).
    private func buildMap(_ curves: [CGFloat]) {
        let n = curves.count
        var th: CGFloat = 0, p = CGPoint.zero
        var raw: [CGPoint] = []
        for i in 0..<n {
            raw.append(p)
            th += -curves[i] / Self.curveK
            p.x += cos(th); p.y += sin(th)
        }
        let gap = p
        raw = raw.enumerated().map { i, q in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: q.x - gap.x * t, y: q.y - gap.y * t)
        }
        let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!, minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
        mapAspect = (maxX - minX) / max(1, maxY - minY)
        map = raw.map { CGPoint(x: ($0.x - minX) / max(1, maxX - minX), y: ($0.y - minY) / max(1, maxY - minY)) }
    }

    /// Closed Catmull-Rom through the (densified) waypoints, resampled at equal arc length.
    static func spline(_ wp: [(CGFloat, CGFloat)], samples: Int) -> [CGPoint] {
        var ctrl: [CGPoint] = []
        for i in 0..<wp.count {
            let a = CGPoint(x: wp[i].0, y: wp[i].1), b = CGPoint(x: wp[(i + 1) % wp.count].0, y: wp[(i + 1) % wp.count].1)
            let len = hypot(b.x - a.x, b.y - a.y)
            let k = max(1, Int(len / 5))
            for j in 0..<k {
                let t = CGFloat(j) / CGFloat(k)
                ctrl.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        let m = ctrl.count
        var dense: [CGPoint] = []
        for i in 0..<m {
            let p0 = ctrl[(i - 1 + m) % m], p1 = ctrl[i], p2 = ctrl[(i + 1) % m], p3 = ctrl[(i + 2) % m]
            for s in 0..<24 {
                let t = CGFloat(s) / 24, t2 = t * t, t3 = t2 * t
                func cr(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                dense.append(CGPoint(x: cr(p0.x, p1.x, p2.x, p3.x), y: cr(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        var cum: [CGFloat] = [0]
        for i in 1...dense.count {
            let a = dense[i - 1], b = dense[i % dense.count]
            cum.append(cum[i - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        let total = cum.last!
        var out: [CGPoint] = [], j = 0
        for s in 0..<samples {
            let target = total * CGFloat(s) / CGFloat(samples)
            while j < dense.count - 1, cum[j + 1] < target { j += 1 }
            let a = dense[j], b = dense[(j + 1) % dense.count]
            let t = (target - cum[j]) / max(0.0001, cum[j + 1] - cum[j])
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return out
    }

    // MARK: scenery

    private func decorate() {
        let n = segs.count
        var rng = RaceRng(UInt64(theme.name.count * 7919 + n))
        func dist0(_ i: Int) -> Int { min(i, n - i) }
        func turning(_ i: Int) -> CGFloat { (-6...6).reduce(0) { $0 + segs[(i + $1 + n) % n].curve } / 13 }

        for i in 0..<n {
            var s = segs[i]
            let bend = turning(i)
            let outer: CGFloat = bend > 0 ? -1 : 1      // outside of the corner
            switch theme.scene {
            case .gp:
                let straight = (i < 70 || i > n - 90)
                if straight {
                    s.wallL = RaceWall(kind: .pit, x: 1.55, h: 150)
                    s.wallR = RaceWall(kind: .stand, x: 2.2, h: 950)
                    if i % 12 == 6 { s.props.append(RaceProp(kind: .lamp, x: -1.62, v: 0)) }
                } else {
                    if s.kerb, abs(bend) > 0.4, i % 3 == 0 { s.props.append(RaceProp(kind: .tyres, x: outer * 2.75, v: rng.next())) }
                    if !s.kerb {
                        s.wallL = RaceWall(kind: .armco, x: 2.2, h: 110)
                        s.wallR = RaceWall(kind: .fence, x: 2.2, h: 230)
                        if i % 14 == 0 { s.props.append(RaceProp(kind: .board, x: (i / 14) % 2 == 0 ? -2.05 : 2.05, v: rng.next())) }
                    } else if abs(bend) > 1.1, i % 30 < 18 {
                        s.wallL = bend > 0 ? nil : RaceWall(kind: .stand, x: 3.2, h: 800)
                        s.wallR = bend > 0 ? RaceWall(kind: .stand, x: 3.2, h: 800) : nil
                    }
                    if i % 90 == 45 { s.props.append(RaceProp(kind: .marshal, x: -outer * 2.4, v: 0)) }
                    if i % 4 == 0 { s.props.append(RaceProp(kind: .tree, x: (rng.next() > 0.5 ? 1 : -1) * rng.range(3.6, 7), v: rng.next())) }
                }
                if i == 4 { s.props.append(RaceProp(kind: .gantry, x: 0, v: 0)) }
                if i % 60 == 30, !straight { s.props.append(RaceProp(kind: .banner, x: outer * 2.35, v: rng.next())) }
            case .coast:
                // sea on the right, cliffs and palms on the left
                if i % 3 == 0 { s.props.append(RaceProp(kind: .palm, x: rng.range(1.6, 2.6), v: rng.next())) }
                if i % 5 == 2 { s.props.append(RaceProp(kind: rng.next() > 0.6 ? .bush : .palm, x: -rng.range(1.5, 2.2), v: rng.next())) }
                s.wallR = RaceWall(kind: .armco, x: 1.32, h: 95)
                s.wallL = (i / 120) % 3 == 2 ? nil : RaceWall(kind: .rock, x: 2.6, h: 1300 + 500 * RK.hash(i / 20))
                if i % 160 == 80 { s.props.append(RaceProp(kind: .hut, x: 2.8, v: rng.next())) }
                if i == n / 2 { s.props.append(RaceProp(kind: .lighthouse, x: 4.2, v: 0)) }
                if s.kerb, abs(bend) > 0.9, i % 6 == 0 { s.props.append(RaceProp(kind: .chevron, x: outer * 1.42, v: bend > 0 ? 1 : 0)) }
                if i == 4 { s.props.append(RaceProp(kind: .gantry, x: 0, v: 1)) }
            case .alpine:
                s.wallL = RaceWall(kind: .snow, x: 1.38, h: 120)
                s.wallR = RaceWall(kind: .snow, x: 1.38, h: 120)
                if abs(bend) > 1.0 {
                    if bend > 0 { s.wallR = RaceWall(kind: .rock, x: 1.6, h: 1600) } else { s.wallL = RaceWall(kind: .rock, x: 1.6, h: 1600) }
                }
                if i % 6 == 0 { s.props.append(RaceProp(kind: .pole, x: -1.2, v: 0)); s.props.append(RaceProp(kind: .pole, x: 1.2, v: 0)) }
                if i % 2 == 0 { s.props.append(RaceProp(kind: .pine, x: (rng.next() > 0.5 ? 1 : -1) * rng.range(1.9, 6), v: rng.next())) }
                if i % 23 == 0 { s.props.append(RaceProp(kind: .rock, x: (rng.next() > 0.5 ? 1 : -1) * rng.range(1.7, 3), v: rng.next())) }
                if i % 150 == 75 { s.props.append(RaceProp(kind: .chalet, x: (rng.next() > 0.5 ? 1 : -1) * 3.4, v: rng.next())) }
                if s.kerb, abs(bend) > 1.3, i % 5 == 0 { s.props.append(RaceProp(kind: .chevron, x: outer * 1.3, v: bend > 0 ? 1 : 0)) }
                if i == 4 { s.props.append(RaceProp(kind: .gantry, x: 0, v: 1)) }
            case .night:
                s.wallL = RaceWall(kind: .building, x: 2.0 + 0.6 * RK.hash(i / 18), h: 2400 + 2600 * RK.hash(i / 18 + 7))
                s.wallR = RaceWall(kind: .building, x: 2.0 + 0.6 * RK.hash(i / 18 + 3), h: 2400 + 2600 * RK.hash(i / 18 + 11))
                if i % 10 == 0 { s.props.append(RaceProp(kind: .lamp, x: -1.38, v: 0)); s.props.append(RaceProp(kind: .lamp, x: 1.38, v: 1)) }
                if s.kerb, abs(bend) > 0.9, i % 4 == 0 { s.props.append(RaceProp(kind: .tyres, x: outer * 1.55, v: rng.next())) }
                if i % 33 == 16 { s.props.append(RaceProp(kind: .board, x: (rng.next() > 0.5 ? 1 : -1) * 1.85, v: rng.next())) }
                if i == 4 { s.props.append(RaceProp(kind: .gantry, x: 0, v: 0)) }
            }
            _ = dist0
            segs[i] = s
        }
    }
}
