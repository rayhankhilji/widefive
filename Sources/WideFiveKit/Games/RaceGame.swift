import AppKit
import AVFoundation

struct CarSpec {
    enum Shape { case supercar, f1, boxy, sedan }
    let name: String
    let top: CGFloat, accel: CGFloat, handling: CGFloat, offroad: CGFloat
    let color: NSColor, glass: NSColor
    let shape: Shape
    var kmh: Int { Int(top / 45) }

    static let all: [CarSpec] = [
        CarSpec(name: "Lamborghini", top: 12800, accel: 7400, handling: 2.5, offroad: 0.42, color: NSColor(hex: "#a4e221"), glass: NSColor(hex: "#14202b"), shape: .supercar),
        CarSpec(name: "F1", top: 13600, accel: 9200, handling: 3.2, offroad: 0.3, color: NSColor(hex: "#e10600"), glass: .black, shape: .f1),
        CarSpec(name: "Land Rover", top: 9400, accel: 4800, handling: 2.0, offroad: 0.92, color: NSColor(hex: "#41623e"), glass: NSColor(hex: "#1d2a33"), shape: .boxy),
        CarSpec(name: "G-Wagon", top: 9800, accel: 5300, handling: 1.9, offroad: 0.85, color: NSColor(hex: "#26262b"), glass: NSColor(hex: "#3a4a5c"), shape: .boxy),
        CarSpec(name: "BMW M5", top: 11500, accel: 6600, handling: 2.4, offroad: 0.5, color: NSColor(hex: "#1c4fa0"), glass: NSColor(hex: "#14202b"), shape: .sedan),
        CarSpec(name: "Audi R8", top: 12200, accel: 7000, handling: 2.7, offroad: 0.45, color: NSColor(hex: "#b8bcc4"), glass: NSColor(hex: "#14202b"), shape: .supercar),
        CarSpec(name: "LaFerrari", top: 13100, accel: 7800, handling: 2.6, offroad: 0.4, color: NSColor(hex: "#d40000"), glass: NSColor(hex: "#14202b"), shape: .supercar),
    ]
}

struct TrackSpec {
    let name: String
    let sky: [NSColor]          // horizon → top
    let grass: [NSColor], rumble: [NSColor], road: [NSColor]
    let lane: NSColor, fog: NSColor
    let hills: CGFloat, curviness: CGFloat, seed: UInt64, scenery: Int

    static let all: [TrackSpec] = [
        TrackSpec(name: "Neon City", sky: [NSColor(hex: "#ff2bd6"), NSColor(hex: "#12002a")],
                  grass: [NSColor(hex: "#1a0730"), NSColor(hex: "#240a42")], rumble: [NSColor(hex: "#ff2bd6"), NSColor(hex: "#21e6ff")],
                  road: [NSColor(hex: "#2b2b3d"), NSColor(hex: "#27273a")], lane: NSColor(hex: "#ffe14d"), fog: NSColor(hex: "#3a0a5a"),
                  hills: 0.4, curviness: 1.0, seed: 7, scenery: 0),
        TrackSpec(name: "Coast", sky: [NSColor(hex: "#ffd29a"), NSColor(hex: "#3f9cff")],
                  grass: [NSColor(hex: "#e8d18a"), NSColor(hex: "#dcc47a")], rumble: [NSColor(hex: "#ffffff"), NSColor(hex: "#e52521")],
                  road: [NSColor(hex: "#5a5a62"), NSColor(hex: "#55555d")], lane: .white, fog: NSColor(hex: "#cfe8ff"),
                  hills: 0.7, curviness: 1.1, seed: 21, scenery: 1),
        TrackSpec(name: "Alpine", sky: [NSColor(hex: "#e6f2ff"), NSColor(hex: "#5f92d6")],
                  grass: [NSColor(hex: "#f2f6fb"), NSColor(hex: "#dfe7f1")], rumble: [NSColor(hex: "#e52521"), NSColor(hex: "#ffffff")],
                  road: [NSColor(hex: "#4a4a52"), NSColor(hex: "#45454d")], lane: NSColor(hex: "#ffd700"), fog: NSColor(hex: "#eef4ff"),
                  hills: 1.6, curviness: 1.3, seed: 99, scenery: 2),
    ]
}

struct RaceSeg { let curve: CGFloat; let y1: CGFloat; let y2: CGFloat }

/// Blocky pseudo-3D arcade racer. Split-screen for two players, or one wide screen vs bots.
public final class RaceGame: StripMode, DemoStartable {
    public let id = "race"
    public let title = "Strip Racer"
    public let icon = "car.fill"
    public let isAnimated = true
    public let refreshInterval = 1.0 / 60
    public let allowsGestures = false
    public let showsExitButton = true
    public var isGame: Bool { true }
    public var isTwoPlayer: Bool { true }

    enum Phase { case setup, garage, countdown, race, results }

    struct Racer {
        var car: Int, d: CGFloat, x: CGFloat
        var speed: CGFloat = 0, human: Int?, name: String, skill: CGFloat, lane: CGFloat
        var nitro: CGFloat = 1, boosting = false, finished: Double?, steer: CGFloat = 0, braking = false
    }

    static let povNames = ["CHASE", "COCKPIT", "HOOD"]
    static let difficulties = ["EASY", "NORMAL", "HARD"]
    private let segLen: CGFloat = 200
    private let roadW: CGFloat = 1600
    private let drawDist = 130
    private let laps = 3

    private let input = DuoInput()
    private var phase = Phase.setup
    private var vsFriend = false
    private var trackIdx = 0
    private var sound = false
    private var audio: RaceAudio?
    private var focus = 4
    private var carPick = [6, 0]
    private var pov = [0, 0]
    private var ready = [false, false]
    private var difficulty = 1
    private var demo = false
    private var segs: [RaceSeg] = []
    private var trackLen: CGFloat = 1
    private var racers: [Racer] = []
    private var humanIdx: [Int] = []
    private var bgOffset: [CGFloat] = [0, 0]
    private var timer: Double = 0
    private var raceTime: Double = 0
    private var finishWait: Double?
    private var lastBeep = 99
    private var setupRects: [CGRect] = []
    private var width: CGFloat = 1004

    private var track: TrackSpec { TrackSpec.all[trackIdx] }
    private var x0: CGFloat { StripController.gameChromeWidth + 2 }

    public init() {}

    public func activate(_ ctx: ModeContext) {
        width = ctx.size.width
        input.width = width
        input.layout = ["L", "R", "D", "F"]
        input.reset()
        phase = .setup
        demo = false
        sound = false          // sound always starts off; turn it on in the menu each time
        audio?.stop(); audio = nil
    }
    public func deactivate() { input.reset(); audio?.stop(); audio = nil; sound = false }

    public func startDemo() {
        demo = true; vsFriend = true; carPick = [6, 3]; pov = [0, 1]; trackIdx = 0
        startRace()
        phase = .race
        for i in racers.indices { racers[i].speed = CarSpec.all[racers[i].car].top * 0.8; racers[i].d += 3000 }
    }

    // MARK: track

    private func buildTrack() {
        var rng = Rng(track.seed)
        var out: [RaceSeg] = []
        var y: CGFloat = 0
        func add(_ n: Int, curve: CGFloat, dy: CGFloat) {
            let y0 = y
            for i in 0..<n {
                let p0 = CGFloat(i) / CGFloat(n), p1 = CGFloat(i + 1) / CGFloat(n)
                let e0 = (1 - cos(p0 * .pi)) / 2, e1 = (1 - cos(p1 * .pi)) / 2
                out.append(RaceSeg(curve: curve * sin(p1 * .pi), y1: y0 + dy * e0, y2: y0 + dy * e1))
            }
            y = y0 + dy
        }
        add(40, curve: 0, dy: 0)
        while out.count < 1250 {
            let n = 40 + Int(rng.next() * 100)
            var curve = (rng.next() * 2 - 1) * 1.6 * track.curviness
            if abs(curve) < 0.35 { curve = 0 }
            let dy = (rng.next() * 2 - 1) * 1400 * track.hills
            add(n, curve: curve, dy: max(-3000, min(3000, y + dy)) - y)
        }
        add(70, curve: 0, dy: -y)
        add(30, curve: 0, dy: 0)
        segs = out
        trackLen = CGFloat(segs.count) * segLen
    }

    private func wrap(_ d: CGFloat) -> CGFloat {
        let m = d.truncatingRemainder(dividingBy: trackLen)
        return m < 0 ? m + trackLen : m
    }
    private func seg(at d: CGFloat) -> RaceSeg { segs[Int(wrap(d) / segLen) % segs.count] }
    private func height(at d: CGFloat) -> CGFloat {
        let z = wrap(d)
        let i = Int(z / segLen) % segs.count
        let t = (z - CGFloat(i) * segLen) / segLen
        return segs[i].y1 + (segs[i].y2 - segs[i].y1) * t
    }

    private func startRace() {
        buildTrack()
        let humans = vsFriend ? 2 : 1
        let bots = vsFriend ? 3 : 5
        let names = ["BLAZE", "NOVA", "TURBO", "VEX", "KILO"].shuffled()
        let base: CGFloat = [0.84, 0.9, 0.96][difficulty]
        racers = []
        let total = humans + bots
        for slot in 0..<total {
            let row = slot / 2
            let x: CGFloat = slot % 2 == 0 ? -0.45 : 0.45
            let d = -CGFloat(row) * 800 - 300
            if slot < bots {
                racers.append(Racer(car: Int.random(in: 0..<CarSpec.all.count), d: d, x: x, human: nil, name: names[slot],
                                    skill: base + CGFloat.random(in: 0...0.04), lane: x))
            } else {
                let h = slot - bots
                racers.append(Racer(car: carPick[h], d: d, x: x, human: h, name: "P\(h + 1)", skill: 0.95, lane: x))
            }
        }
        humanIdx = (0..<humans).map { h in racers.firstIndex { $0.human == h }! }
        bgOffset = [0, 0]
        raceTime = 0
        finishWait = nil
        lastBeep = 99
        phase = .countdown
        timer = 3.5
        input.clearEdges()
    }

    private func held(_ p: Int, _ b: String) -> Bool {
        vsFriend ? input.isDown(p, b) : (input.isDown(0, b) || input.isDown(1, b))
    }

    // MARK: update

    public func update(dt: Double) {
        let d = CGFloat(min(dt, 1.0 / 20))
        timer -= dt
        switch phase {
        case .setup:
            for p in 0..<2 {
                if input.take(p, "L") { focus = max(0, focus - 1) }
                if input.take(p, "R") { focus = min(4, focus + 1) }
                if input.take(p, "D"), focus == 2 { trackIdx = (trackIdx + TrackSpec.all.count - 1) % TrackSpec.all.count }
                if input.take(p, "F") || input.take(p, "U") { pickSetup(focus) }
            }
        case .garage:
            let n = CarSpec.all.count
            for p in 0..<2 {
                let pl = vsFriend ? p : 0
                if input.take(p, "S"), !vsFriend { difficulty = (difficulty + 1) % 3 }
                if ready[pl] { if input.take(p, "F") { ready[pl] = false }; continue }
                if input.take(p, "L") { carPick[pl] = (carPick[pl] + n - 1) % n }
                if input.take(p, "R") { carPick[pl] = (carPick[pl] + 1) % n }
                if input.take(p, "U") || input.take(p, "D") { pov[pl] = (pov[pl] + 1) % 3 }
                if input.take(p, "F") { ready[pl] = true }
            }
            if vsFriend ? (ready[0] && ready[1]) : ready[0] { startRace() }
        case .countdown:
            let n = Int(ceil(timer))
            if n != lastBeep { lastBeep = n; if sound, n <= 3 { audio?.beep(n <= 0) } }
            if timer <= 0 { phase = .race; input.clearEdges() }
            updateAudio()
        case .race:
            raceTime += dt
            for i in racers.indices { stepRacer(i, d) }
            collide()
            if finishWait == nil, humanIdx.allSatisfy({ racers[$0].finished != nil }) { finishWait = 2.5 }
            if let w = finishWait {
                finishWait = w - dt
                if w - dt <= 0 { phase = .results; timer = 0.8; audio?.silence() }
            }
            updateAudio()
        case .results:
            if timer <= 0, input.take(0, "F") || input.take(1, "F") || input.take(0, "U") || input.take(1, "U") {
                phase = .setup; input.clearEdges()
            }
            if demo, timer < -3 { startDemo() }
        }
    }

    private func pickSetup(_ i: Int) {
        switch i {
        case 0: vsFriend = false
        case 1: vsFriend = true
        case 2: trackIdx = (trackIdx + 1) % TrackSpec.all.count
        case 3:
            sound.toggle()
            if sound { if audio == nil { audio = RaceAudio() }; audio?.start() } else { audio?.stop(); audio = nil }
        default:
            phase = .garage
            ready = [false, false]
            input.clearEdges()
        }
    }

    private func stepRacer(_ i: Int, _ d: CGFloat) {
        var r = racers[i]
        let spec = CarSpec.all[r.car]
        let s = seg(at: r.d)
        var gas = false, brake = false, steer: CGFloat = 0, wantNitro = false
        if let p = r.human, !demo {
            steer = (held(p, "R") ? 1 : 0) - (held(p, "L") ? 1 : 0)
            brake = held(p, "D")
            gas = held(p, "U") || (!input.usedKeyboard && !brake)
            wantNitro = held(p, "F")
        } else {
            for (j, o) in racers.enumerated() where j != i {
                let rel = o.d - r.d
                if rel > 0, rel < 1000, abs(o.x - r.x) < 0.5 { r.lane = o.x > 0 ? max(-0.8, o.x - 0.75) : min(0.8, o.x + 0.75) }
            }
            let target = r.lane - s.curve * 0.22
            steer = max(-1, min(1, (target - r.x) * 3))
            let want = spec.top * r.skill * (1 - min(0.22, abs(s.curve) * 0.07))
            gas = r.speed < want
            brake = r.speed > want * 1.1
            wantNitro = r.nitro > 0.6 && abs(s.curve) < 0.2 && r.skill > 0.9
        }
        r.boosting = wantNitro && r.nitro > 0.02 && gas
        r.nitro = r.boosting ? r.nitro - 0.45 * d : min(1, r.nitro + 0.07 * d)
        let topNow = spec.top * (r.boosting ? 1.22 : 1)
        let offroad = abs(r.x) > 1.08
        let cap = offroad ? spec.top * spec.offroad : topNow
        if gas { r.speed += spec.accel * (r.boosting ? 1.6 : 1) * max(0.05, 1 - 0.55 * r.speed / topNow) * d } else if brake { r.speed -= 14000 * d } else { r.speed -= 2500 * d }
        if r.speed > cap { r.speed = max(cap, r.speed - (offroad ? 2.5 : 1.2) * spec.accel * d) }
        r.speed = max(0, r.speed)
        let pct = r.speed / spec.top
        r.steer += (steer - r.steer) * min(1, d * 10)
        r.x += r.steer * d * spec.handling * 0.55 * min(1, r.speed / 2500)
        r.x -= d * pct * s.curve * 0.42
        r.x = max(-2.3, min(2.3, r.x))
        r.braking = brake
        r.d += r.speed * d
        if r.finished == nil, r.d >= CGFloat(laps) * trackLen { r.finished = raceTime }
        if let p = r.human { bgOffset[p] += s.curve * pct * d * 30 }
        racers[i] = r
    }

    private func collide() {
        for i in racers.indices {
            for j in racers.indices where j > i {
                let dz = racers[j].d - racers[i].d
                guard abs(dz) < 320, abs(racers[i].x - racers[j].x) < 0.4 else { continue }
                let behind = dz > 0 ? i : j, ahead = dz > 0 ? j : i
                racers[behind].speed = min(racers[behind].speed, racers[ahead].speed * 0.92)
                racers[behind].x += racers[behind].x < racers[ahead].x ? -0.04 : 0.04
            }
        }
    }

    private func ranking() -> [Int] {
        racers.indices.sorted { a, b in
            switch (racers[a].finished, racers[b].finished) {
            case let (fa?, fb?): return fa < fb
            case (.some, nil): return true
            case (nil, .some): return false
            default: return racers[a].d > racers[b].d
            }
        }
    }

    private func updateAudio() {
        guard sound, let audio else { return }
        for v in 0..<2 {
            guard v < humanIdx.count else { audio.set(v, rpm: 0, on: false); continue }
            let r = racers[humanIdx[v]]
            let pct = Double(r.speed / CarSpec.all[r.car].top)
            let gear = min(5, Int(pct * 6))
            audio.set(v, rpm: (pct * 6 - Double(gear)) * 0.8 + 0.3 + Double(gear) * 0.05, on: true)
        }
    }

    // MARK: touch

    public func touchBegan(_ t: StripTouch) {
        switch phase {
        case .setup:
            guard let i = setupRects.firstIndex(where: { t.x >= $0.minX && t.x <= $0.maxX }) else { return }
            focus = i
            if i == 2, t.x < setupRects[2].midX { trackIdx = (trackIdx + TrackSpec.all.count - 1) % TrackSpec.all.count } else { pickSetup(i) }
        case .garage:
            garageTouch(t.x)
        case .results:
            if timer <= 0 { phase = .setup }
        default:
            input.began(t)
        }
    }
    public func touchMoved(_ t: StripTouch) { input.moved(t) }
    public func touchEnded(_ t: StripTouch) { input.ended(t) }
    public func touchCancelled(_ t: StripTouch) { input.ended(t) }
    public func keyDown(_ key: GameKey) { input.key(key, down: true) }
    public func keyUp(_ key: GameKey) { input.key(key, down: false) }

    private func garageTouch(_ x: CGFloat) {
        let mid = (x0 + width) / 2
        let p = x < mid ? 0 : 1
        if p == 1, !vsFriend { difficulty = (difficulty + 1) % 3; return }
        let hx0 = p == 0 ? x0 : mid, hw = (p == 0 ? mid : width) - hx0
        let rx = x - hx0, n = CarSpec.all.count
        if rx < 24 { carPick[p] = (carPick[p] + n - 1) % n; ready[p] = false } else if rx > hw - 24 { carPick[p] = (carPick[p] + 1) % n; ready[p] = false } else if rx > hw - 82 { ready[p].toggle() } else if rx > hw - 152 { pov[p] = (pov[p] + 1) % 3 } else { carPick[p] = (carPick[p] + 1) % n; ready[p] = false }
        if vsFriend ? (ready[0] && ready[1]) : ready[0] { startRace() }
    }

    // MARK: draw

    public func draw(_ c: Canvas) {
        width = c.width
        input.width = width
        input.players = vsFriend ? 2 : 1
        switch phase {
        case .setup: drawSetup(c); return
        case .garage: drawGarage(c); return
        default: break
        }
        let rects = viewRects(c)
        for (p, r) in rects.enumerated() { c.clip(r) { renderView(c, r, humanIdx[p], player: p) } }
        if rects.count == 2 {
            c.fill(CGRect(x: rects[0].maxX, y: 0, width: rects[1].minX - rects[0].maxX, height: 30), .black)
        }
        if phase == .countdown {
            let n = Int(ceil(timer))
            for r in rects {
                let s = n > 3 ? "READY" : n > 0 ? "\(n)" : "GO!"
                c.roundRect(CGRect(x: r.midX - 34, y: 6, width: 68, height: 18), radius: 6, fill: NSColor(white: 0, alpha: 0.6))
                c.text(s, x: r.midX, size: 13, color: n > 0 ? Pal.yellow : NSColor(hex: "#3ddc84"), weight: .black, align: .center)
            }
        }
        if phase == .results {
            let order = ranking()
            let line = order.enumerated().map { "\($0.offset + 1). \(racers[$0.element].name) (\(CarSpec.all[racers[$0.element].car].name))" }.joined(separator: "  ")
            let winner = racers[order[0]]
            Arcade.banner(c, "🏁 \(winner.name) WINS · \(timeString(winner.finished ?? raceTime))", line + "   · tap / F", accent: Pal.yellow, width: min(c.width - 80, 860))
        }
        input.draw(c, colors: [Pal.cyan, Pal.magenta])
    }

    private func timeString(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }

    private func viewRects(_ c: Canvas) -> [CGRect] {
        let left = StripController.gameChromeWidth
        if vsFriend {
            let mid = (left + c.width) / 2
            return [CGRect(x: left, y: 0, width: mid - left - 1, height: c.height), CGRect(x: mid + 1, y: 0, width: c.width - mid - 1, height: c.height)]
        }
        return [CGRect(x: left, y: 0, width: c.width - left, height: c.height)]
    }

    private struct Quad { let k: Int, idx: Int, sx1: CGFloat, sy1: CGFloat, w1: CGFloat, sx2: CGFloat, sy2: CGFloat, w2: CGFloat }

    private func renderView(_ c: Canvas, _ rect: CGRect, _ ri: Int, player: Int) {
        let me = racers[ri]
        let t = track
        let cams: [(h: CGFloat, depth: CGFloat, behind: CGFloat)] = [(1000, 0.84, 840), (430, 1.0, 0), (560, 0.95, 0)]
        let cam = cams[pov[player]]
        let H = rect.height
        let xK = 100 + max(0, rect.width - 470) * 0.09
        let yK = H * 0.62
        let horizon = rect.minY + H * 0.66
        let camD = me.d - cam.behind
        let camZ = wrap(camD)
        let base = Int(camZ / segLen)
        let frac = camZ - CGFloat(base) * segLen
        let offroad = abs(me.x) > 1.08 && me.speed > 500
        let shake: CGFloat = offroad ? sin(CGFloat(c.time) * 50) * 25 : 0
        let camY = cam.h + height(at: me.d) + shake
        let camX = me.x * roadW
        let n = segs.count

        c.gradient(CGRect(x: rect.minX, y: horizon - 1, width: rect.width, height: rect.maxY - horizon + 1), t.sky)
        drawBackdrop(c, rect, horizon, bgOffset[player])
        c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: horizon - rect.minY), t.grass[0].blended(withFraction: 0.5, of: t.fog) ?? t.grass[0])

        var x: CGFloat = 0
        var dx: CGFloat = -segs[base % n].curve * frac / segLen
        var quads: [Quad] = []
        var xs = [CGFloat](repeating: 0, count: drawDist), dxs = xs
        for k in 0..<drawDist {
            let idx = (base + k) % n
            let s = segs[idx]
            let z1 = CGFloat(k) * segLen - frac, z2 = z1 + segLen
            xs[k] = x; dxs[k] = dx
            let x1 = x, x2 = x + dx
            x += dx; dx += s.curve
            guard z2 > 20 else { continue }
            let s1 = cam.depth / max(z1, 20), s2 = cam.depth / z2
            quads.append(Quad(k: k, idx: idx,
                              sx1: rect.midX + (x1 - camX) * s1 * xK, sy1: horizon + (s.y1 - camY) * s1 * yK, w1: roadW * s1 * xK,
                              sx2: rect.midX + (x2 - camX) * s2 * xK, sy2: horizon + (s.y2 - camY) * s2 * yK, w2: roadW * s2 * xK))
        }
        func fog(_ k: Int) -> CGFloat { min(1, pow(CGFloat(k) / CGFloat(drawDist), 1.6)) }
        func mix(_ col: NSColor, _ f: CGFloat) -> NSColor { col.blended(withFraction: f, of: t.fog) ?? col }
        func trap(_ q: Quad, _ m: CGFloat, _ off: CGFloat = 0) -> [CGPoint] {
            [CGPoint(x: q.sx1 + q.w1 * (off - m), y: q.sy1), CGPoint(x: q.sx1 + q.w1 * (off + m), y: q.sy1),
             CGPoint(x: q.sx2 + q.w2 * (off + m), y: q.sy2), CGPoint(x: q.sx2 + q.w2 * (off - m), y: q.sy2)]
        }
        for q in quads.reversed() {
            let f = fog(q.k)
            let alt = (q.idx / 3) % 2 == 0
            if q.sy2 > q.sy1 {
                c.fill(CGRect(x: rect.minX, y: q.sy1, width: rect.width, height: q.sy2 - q.sy1 + 0.4), mix(alt ? t.grass[0] : t.grass[1], f))
            }
            c.polygon(trap(q, 1.14), mix(alt ? t.rumble[0] : t.rumble[1], f))
            c.polygon(trap(q, 1), mix(alt ? t.road[0] : t.road[1], f))
            if q.idx < 2 {
                c.polygon(trap(q, 1), mix(.white, f))
            } else if alt {
                for lane: CGFloat in [-0.333, 0.333] { c.polygon(trap(q, 0.025, lane), mix(t.lane, f)) }
            }
        }

        var sprites: [(CGFloat, () -> Void)] = []
        for k in stride(from: 1, to: drawDist, by: 1) {
            let idx = (base + k) % n
            guard idx % 5 == 0 else { continue }
            let z = CGFloat(k) * segLen - frac
            guard z > 40 else { continue }
            let s = cam.depth / z, u = s * xK
            for side: CGFloat in [-1, 1] {
                let h = Self.hash(idx &* 3 &+ (side > 0 ? 1 : 0))
                let lat = xs[k] + side * roadW * (1.3 + 0.9 * h)
                let sx = rect.midX + (lat - camX) * u
                guard sx > rect.minX - 150, sx < rect.maxX + 150 else { continue }
                let sy = horizon + (segs[idx].y1 - camY) * s * yK
                let f = fog(k)
                sprites.append((z, { self.drawScenery(c, t.scenery, sx, sy, u, idx, side, f) }))
            }
        }
        for (j, o) in racers.enumerated() {
            if j == ri && pov[player] != 0 { continue }
            let rel = wrap(o.d - camD)
            guard rel > 60, rel < CGFloat(drawDist - 2) * segLen else { continue }
            let k = Int((rel + frac) / segLen)
            guard k < drawDist else { continue }
            let tt = (rel - (CGFloat(k) * segLen - frac)) / segLen
            let lat = xs[k] + dxs[k] * tt
            let s = cam.depth / rel
            let sx = rect.midX + (lat + o.x * roadW - camX) * s * xK
            let sy = horizon + (height(at: o.d) - camY) * s * yK
            let w = 700 * s * xK
            sprites.append((rel, { RaceGame.drawCar(c, CarSpec.all[o.car], cx: sx, by: sy, w: w, steer: o.steer, brake: o.braking, boost: o.boosting) }))
        }
        for spr in sprites.sorted(by: { $0.0 > $1.0 }) { spr.1() }

        let spec = CarSpec.all[me.car]
        if pov[player] == 1 { drawCockpit(c, rect, me, spec) }
        if pov[player] == 2 {
            let w = rect.width
            c.polygon([CGPoint(x: rect.midX - w * 0.3, y: rect.minY), CGPoint(x: rect.midX + w * 0.3, y: rect.minY),
                       CGPoint(x: rect.midX + w * 0.17, y: rect.minY + 5), CGPoint(x: rect.midX - w * 0.17, y: rect.minY + 5)], spec.color)
            c.fill(CGRect(x: rect.midX - w * 0.12, y: rect.minY + 3.5, width: w * 0.24, height: 0.8), NSColor(white: 1, alpha: 0.35))
        }
        drawHUD(c, rect, me, ri, player)
    }

    private static func hash(_ i: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(i)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return CGFloat(x % 10_000) / 10_000
    }

    private func drawBackdrop(_ c: Canvas, _ rect: CGRect, _ horizon: CGFloat, _ offset: CGFloat) {
        let t = track
        switch t.scenery {
        case 0:
            let step: CGFloat = 16
            let shift = offset.truncatingRemainder(dividingBy: step)
            let first = Int((offset / step).rounded(.down))
            for i in 0..<Int(rect.width / step) + 2 {
                let h = 3 + Self.hash(first + i) * 8
                let bx = rect.minX + CGFloat(i) * step - shift
                c.fill(CGRect(x: bx, y: horizon - 1, width: step - 2, height: h), NSColor(hex: "#1b0636"))
                if Self.hash(first + i + 500) > 0.4 {
                    c.fill(CGRect(x: bx + 3, y: horizon + h * 0.5, width: 1, height: 1), Self.hash(first + i + 900) > 0.5 ? Pal.yellow : Pal.magenta)
                }
            }
        case 1:
            c.circle(center: CGPoint(x: rect.midX + 60 - offset.truncatingRemainder(dividingBy: rect.width), y: horizon + 4), radius: 5, NSColor(hex: "#ffb347"))
            c.fill(CGRect(x: rect.minX, y: horizon - 1, width: rect.width, height: 2.5), NSColor(hex: "#2a7fd4"))
        default:
            let step: CGFloat = 46
            let shift = (offset * 0.6).truncatingRemainder(dividingBy: step)
            let first = Int((offset * 0.6 / step).rounded(.down))
            for i in -1..<Int(rect.width / step) + 2 {
                let h = 5 + Self.hash(first + i) * 8
                let cx = rect.minX + CGFloat(i) * step - shift + step / 2
                c.polygon([CGPoint(x: cx - 30, y: horizon - 1), CGPoint(x: cx + 30, y: horizon - 1), CGPoint(x: cx, y: horizon + h)], NSColor(hex: "#7a8fb0"))
                c.polygon([CGPoint(x: cx - 30 * 0.3, y: horizon + h * 0.7), CGPoint(x: cx + 30 * 0.3, y: horizon + h * 0.7), CGPoint(x: cx, y: horizon + h)], .white)
            }
        }
    }

    private func drawScenery(_ c: Canvas, _ kind: Int, _ sx: CGFloat, _ sy: CGFloat, _ u: CGFloat, _ idx: Int, _ side: CGFloat, _ fog: CGFloat) {
        guard u * 300 > 0.6 else { return }
        func m(_ col: NSColor) -> NSColor { col.blended(withFraction: fog, of: track.fog) ?? col }
        switch kind {
        case 0:
            if idx % 10 == 0 {
                c.fill(CGRect(x: sx - 40 * u, y: sy, width: 80 * u, height: 1300 * u * 0.3), m(NSColor(hex: "#3a3a4a")))
                c.fill(CGRect(x: sx - (side > 0 ? 300 : 0) * u, y: sy + 1300 * u * 0.3, width: 300 * u, height: 50 * u * 0.4 + 0.5), m(Pal.cyan))
            } else {
                let h = (900 + 900 * Self.hash(idx)) * u * 0.3
                c.fill(CGRect(x: sx - 350 * u, y: sy, width: 700 * u, height: h), m(NSColor(hex: "#24104a")))
                c.fill(CGRect(x: sx - 350 * u, y: sy + h - 30 * u, width: 700 * u, height: max(0.5, 30 * u)), m(Self.hash(idx + 3) > 0.5 ? Pal.magenta : Pal.cyan))
            }
        case 1:
            let th = 900 * u * 0.3
            c.fill(CGRect(x: sx - 30 * u, y: sy, width: 60 * u, height: th), m(NSColor(hex: "#8b5a2b")))
            for k in -1...1 {
                c.fill(CGRect(x: sx - 200 * u + CGFloat(k) * 120 * u, y: sy + th - CGFloat(abs(k)) * 60 * u * 0.3, width: 400 * u, height: 80 * u * 0.3 + 0.5), m(NSColor(hex: "#2e9e44")))
            }
        default:
            c.fill(CGRect(x: sx - 40 * u, y: sy, width: 80 * u, height: 200 * u * 0.3), m(NSColor(hex: "#5b3a1e")))
            for k in 0..<3 {
                let w = (500 - CGFloat(k) * 140) * u
                let y = sy + (200 + CGFloat(k) * 300) * u * 0.3
                c.fill(CGRect(x: sx - w / 2, y: y, width: w, height: 300 * u * 0.3), m(NSColor(hex: "#1f5e3a")))
                c.fill(CGRect(x: sx - w / 2, y: y + 240 * u * 0.3, width: w, height: 60 * u * 0.3), m(.white))
            }
        }
    }

    static func drawCar(_ c: Canvas, _ s: CarSpec, cx: CGFloat, by: CGFloat, w: CGFloat, steer: CGFloat = 0, brake: Bool = false, boost: Bool = false) {
        guard w > 1.5 else { return }
        let ratio: CGFloat = s.shape == .boxy ? 0.42 : s.shape == .f1 ? 0.3 : 0.3
        let h = min(w * ratio, 20)
        let x0 = cx - w / 2
        func r(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat, _ col: NSColor) {
            c.fill(CGRect(x: x0 + fx * w + steer * w * 0.04 * fy, y: by + fy * h, width: fw * w, height: fh * h), col)
        }
        c.fill(CGRect(x: x0 - w * 0.04, y: by - h * 0.08, width: w * 1.08, height: h * 0.12), NSColor(white: 0, alpha: 0.35))
        let tail = brake ? NSColor(hex: "#ff3030") : NSColor(hex: "#a01010")
        let dark = s.color.blended(withFraction: 0.45, of: .black) ?? s.color
        let metal = NSColor(white: 0.12, alpha: 1)
        switch s.shape {
        case .supercar:
            r(0.02, 0, 0.14, 0.28, .black); r(0.84, 0, 0.14, 0.28, .black)
            r(0, 0.12, 1, 0.42, s.color)
            r(0.06, 0.54, 0.88, 0.1, dark)
            r(0.2, 0.62, 0.6, 0.26, s.glass)
            r(0.18, 0.86, 0.64, 0.06, s.color)
            r(0.05, 0.36, 0.3, 0.07, tail); r(0.65, 0.36, 0.3, 0.07, tail)
            r(0.38, 0.14, 0.24, 0.1, metal)
        case .f1:
            r(0, 0, 0.22, 0.5, .black); r(0.78, 0, 0.22, 0.5, .black)
            r(0.33, 0.08, 0.34, 0.45, s.color)
            r(0.42, 0.53, 0.16, 0.22, dark)
            r(0.47, 0.45, 0.06, 0.45, metal)
            r(0.12, 0.85, 0.76, 0.15, s.color)
            r(0.12, 0.8, 0.76, 0.05, dark)
            r(0.46, 0.12, 0.08, 0.08, tail)
        case .boxy:
            r(0.04, 0, 0.14, 0.24, .black); r(0.82, 0, 0.14, 0.24, .black)
            r(0.02, 0.14, 0.96, 0.5, s.color)
            r(0.06, 0.64, 0.88, 0.3, s.glass)
            r(0.04, 0.92, 0.92, 0.08, s.color)
            r(0.36, 0.22, 0.28, 0.32, metal)
            r(0.05, 0.4, 0.08, 0.14, tail); r(0.87, 0.4, 0.08, 0.14, tail)
        case .sedan:
            r(0.04, 0, 0.13, 0.25, .black); r(0.83, 0, 0.13, 0.25, .black)
            r(0.01, 0.12, 0.98, 0.46, s.color)
            r(0.14, 0.58, 0.72, 0.3, s.glass)
            r(0.12, 0.86, 0.76, 0.07, s.color)
            r(0.04, 0.4, 0.26, 0.08, tail); r(0.7, 0.4, 0.26, 0.08, tail)
            r(0.2, 0.14, 0.1, 0.06, metal); r(0.7, 0.14, 0.1, 0.06, metal)
        }
        if boost {
            c.fill(CGRect(x: cx - w * 0.14, y: by + h * 0.12, width: w * 0.28, height: max(1, h * 0.12)), Pal.cyan)
            c.fill(CGRect(x: cx - w * 0.08, y: by + h * 0.02, width: w * 0.16, height: max(1, h * 0.1)), Pal.orange)
        }
    }

    private func drawCockpit(_ c: Canvas, _ rect: CGRect, _ r: Racer, _ spec: CarSpec) {
        let dark = NSColor(hex: "#0d0d10")
        c.polygon([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + 30, y: rect.minY), CGPoint(x: rect.minX + 8, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)], dark)
        c.polygon([CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX - 30, y: rect.minY), CGPoint(x: rect.maxX - 8, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)], dark)
        c.fill(CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2), dark)
        c.roundRect(CGRect(x: rect.midX - 22, y: rect.maxY - 6, width: 44, height: 4), radius: 1.5, fill: NSColor(hex: "#2a2a30"))
        c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 6), dark)
        c.fill(CGRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 0.8), spec.color.withAlphaComponent(0.8))
        let wc = CGPoint(x: rect.midX + r.steer * 2, y: rect.minY + 1)
        c.circle(center: wc, radius: 11, NSColor(hex: "#25252b"))
        c.circle(center: wc, radius: 8, dark)
        c.fill(CGRect(x: wc.x - 1 + r.steer * 7, y: wc.y + 9, width: 2, height: 2), spec.color)
        c.text("\(Int(r.speed / 45))", x: rect.midX + 34, y: rect.minY + 0.5, size: 6, color: spec.color, weight: .black, mono: true, align: .center)
    }

    private func drawHUD(_ c: Canvas, _ rect: CGRect, _ me: Racer, _ ri: Int, _ player: Int) {
        let accent = player == 0 ? Pal.cyan : Pal.magenta
        let pos = (ranking().firstIndex(of: ri) ?? 0) + 1
        let lap = min(laps, Int(max(0, me.d) / trackLen) + 1)
        let left = rect.minX + (pov[player] == 1 ? 32 : 4)
        let right = rect.maxX - (pov[player] == 1 ? 32 : 4)
        c.roundRect(CGRect(x: left - 2, y: 19.5, width: 112, height: 9), radius: 3, fill: NSColor(white: 0, alpha: 0.45))
        c.text("P\(player + 1)", x: left, y: 20.5, size: 7, color: accent, weight: .black)
        c.text("POS \(pos)/\(racers.count)", x: left + 15, y: 20.5, size: 7, color: .white, weight: .bold, mono: true)
        c.text(me.finished != nil ? "FINISH" : "LAP \(lap)/\(laps)", x: left + 64, y: 20.5, size: 7, color: .white, weight: .bold, mono: true)
        c.roundRect(CGRect(x: right - 64, y: 19.5, width: 66, height: 9), radius: 3, fill: NSColor(white: 0, alpha: 0.45))
        c.text("\(Int(me.speed / 45)) km/h", x: right, y: 20.5, size: 7, color: me.boosting ? Pal.cyan : .white, weight: .bold, mono: true, align: .right)
        c.fill(CGRect(x: right - 62, y: 18, width: 62, height: 1.2), NSColor(white: 1, alpha: 0.15))
        c.fill(CGRect(x: right - 62, y: 18, width: 62 * me.nitro, height: 1.2), me.boosting ? Pal.cyan : Pal.orange)
    }

    private func drawSetup(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#0a0a18"), NSColor(hex: "#1d0b33")])
        let left = x0 + 4
        c.text("STRIP", x: left, y: 15, size: 9, color: Pal.cyan, weight: .black)
        c.text("RACER", x: left, y: 4, size: 11, color: Pal.magenta, weight: .black)
        var x = left + 50
        let items: [(String, CGFloat)] = [("VS BOTS", 74), ("VS FRIEND", 84), ("◀ \(track.name.uppercased()) ▶", 134),
                                          (sound ? "🔊 SOUND ON" : "🔇 SOUND OFF", 104), ("GARAGE ▶", 88)]
        setupRects = []
        for (i, it) in items.enumerated() {
            let r = CGRect(x: x, y: 3, width: it.1, height: 24)
            let sel = (i == 0 && !vsFriend) || (i == 1 && vsFriend) || (i == 3 && sound)
            let fill = i == 4 ? Pal.magenta.withAlphaComponent(0.85) : sel ? Pal.cyan.withAlphaComponent(0.75) : NSColor(white: 0.12, alpha: 1)
            c.roundRect(r, radius: 7, fill: fill, stroke: focus == i ? .white : nil, lineWidth: 1.2)
            c.text(it.0, x: r.midX, size: 9, color: sel || i == 4 ? .black : .white, weight: .heavy, align: .center)
            setupRects.append(r)
            x += it.1 + 6
        }
        c.text("P1  WASD · F nitro      P2  arrows · / nitro      ⌃⌥⌘K locks keys", x: x + 6, size: 8, color: NSColor(white: 0.62, alpha: 1), maxWidth: c.width - x - 12)
    }

    private func drawGarage(_ c: Canvas) {
        c.gradient(c.bounds, [NSColor(hex: "#0a0a18"), NSColor(hex: "#151530")])
        let mid = (x0 + width) / 2
        drawGaragePanel(c, x0, mid - 2, 0)
        if vsFriend { drawGaragePanel(c, mid + 2, width - 2, 1) } else {
            let r = CGRect(x: mid + 2, y: 1, width: width - mid - 4, height: 28)
            c.roundRect(r, radius: 7, fill: NSColor(white: 0.07, alpha: 1), stroke: Pal.magenta.withAlphaComponent(0.4), lineWidth: 1)
            c.text("5 BOTS · \(track.name.uppercased()) · \(laps) LAPS", x: r.minX + 10, size: 9, color: .white, weight: .heavy)
            let d = CGRect(x: r.maxX - 120, y: 5, width: 110, height: 20)
            c.roundRect(d, radius: 6, fill: Pal.magenta.withAlphaComponent(0.3), stroke: Pal.magenta, lineWidth: 1)
            c.text("AI: \(Self.difficulties[difficulty]) ↻", x: d.midX, size: 8, color: .white, weight: .bold, align: .center)
        }
    }

    private func drawGaragePanel(_ c: Canvas, _ hx0: CGFloat, _ hx1: CGFloat, _ p: Int) {
        let hw = hx1 - hx0
        let accent = p == 0 ? Pal.cyan : Pal.magenta
        let spec = CarSpec.all[carPick[p]]
        c.roundRect(CGRect(x: hx0, y: 1, width: hw, height: 28), radius: 7, fill: NSColor(white: 0.07, alpha: 1),
                    stroke: ready[p] ? Pal.yellow : accent.withAlphaComponent(0.5), lineWidth: ready[p] ? 1.5 : 1)
        c.text("◀", x: hx0 + 11, size: 12, color: accent, weight: .heavy, align: .center)
        c.text("▶", x: hx1 - 11, size: 12, color: accent, weight: .heavy, align: .center)
        c.fill(CGRect(x: hx0 + 26, y: 3, width: 78, height: 1.2), accent.withAlphaComponent(0.4))
        RaceGame.drawCar(c, spec, cx: hx0 + 65, by: 4.5, w: 54)
        let infoW = hw - 262
        c.text("P\(p + 1)  \(spec.name.uppercased())  \(spec.kmh) km/h", x: hx0 + 110, y: 16, size: 9, color: .white, weight: .black, maxWidth: infoW)
        let stats: [(String, CGFloat)] = [("TOP", (spec.top - 9000) / 4800), ("ACC", (spec.accel - 4500) / 5000),
                                          ("HND", (spec.handling - 1.8) / 1.5), ("OFF", (spec.offroad - 0.28) / 0.7)]
        let sw = infoW / 4
        for (i, st) in stats.enumerated() {
            let sx = hx0 + 110 + CGFloat(i) * sw
            c.text(st.0, x: sx, y: 7.5, size: 5.5, color: NSColor(white: 0.6, alpha: 1), weight: .bold)
            c.fill(CGRect(x: sx, y: 4, width: sw - 8, height: 2.5), NSColor(white: 0.2, alpha: 1))
            c.fill(CGRect(x: sx, y: 4, width: (sw - 8) * max(0.08, min(1, st.1)), height: 2.5), accent)
        }
        let vr = CGRect(x: hx1 - 150, y: 5, width: 66, height: 20)
        c.roundRect(vr, radius: 6, fill: NSColor(white: 0.14, alpha: 1))
        c.text("👁 \(Self.povNames[pov[p]])", x: vr.midX, size: 8, color: .white, weight: .bold, align: .center, maxWidth: 64)
        let rr = CGRect(x: hx1 - 80, y: 5, width: 56, height: 20)
        c.roundRect(rr, radius: 6, fill: ready[p] ? NSColor(hex: "#3ddc84") : accent.withAlphaComponent(0.3))
        c.text(ready[p] ? "READY ✓" : "READY", x: rr.midX, size: 8, color: ready[p] ? .black : .white, weight: .heavy, align: .center)
    }
}

private struct Rng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 1_000_000) / 1_000_000
    }
}

/// Two sawtooth engine voices + countdown blips. Only created when sound is switched on.
final class RaceAudio {
    final class State { var freq: [Double] = [0, 0]; var vol: [Double] = [0, 0]; var phase: [Double] = [0, 0] }
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let state = State()

    func start() {
        guard node == nil else { return }
        let st = state
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = sr > 0 ? sr : 44100
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frames) {
                var s = 0.0
                for v in 0..<2 where st.vol[v] > 0 {
                    st.phase[v] += st.freq[v] / rate
                    if st.phase[v] >= 1 { st.phase[v] -= 1 }
                    let ph = st.phase[v]
                    s += ((ph * 2 - 1) * 0.6 + (ph < 0.5 ? 0.4 : -0.4)) * st.vol[v]
                }
                for b in bufs { b.mData?.assumingMemoryBound(to: Float.self)[f] = Float(s * 0.08) }
            }
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        do { try engine.start(); node = n } catch { engine.detach(n) }
    }

    func stop() {
        engine.stop()
        if let n = node { engine.detach(n) }
        node = nil
    }
    func silence() { state.vol = [0, 0] }
    func set(_ v: Int, rpm: Double, on: Bool) { state.freq[v] = 45 + rpm * 140; state.vol[v] = on ? 0.6 : 0 }
    func beep(_ go: Bool) { NSSound(named: go ? "Glass" : "Tink")?.play() }
}
