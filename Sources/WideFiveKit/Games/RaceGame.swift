import AppKit

/// Strip Racer: pseudo-3D arcade racer. Speedometer clusters on the outside, a live minimap of the real
/// circuit in the middle and true-perspective driving viewports in between. Art/rendering lives in Games/Race/.
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
        var car: Int, paint: RCol, d: CGFloat, x: CGFloat
        var speed: CGFloat = 0, human: Int?, name: String, skill: CGFloat, lane: CGFloat
        var nitro: CGFloat = 1, boosting = false, finished: Double?, steer: CGFloat = 0, braking = false
        var wheel: CGFloat = 0, wing: CGFloat = 0, lap = 0, lapStart: Double = 0, lastLap: Double?, bestLap: Double?
        var spec: RaceCar { RaceCar.all[car] }
    }

    struct Particle { var x, y, vx, vy, rot, vr: CGFloat; var life: CGFloat; var col: RCol; var view: Int }

    struct Layout { var gauges: [CGRect]; var views: [CGRect]; var map: CGRect; var board: CGRect? }

    static let povNames = ["CHASE", "COCKPIT", "HOOD"]
    static let difficulties = ["EASY", "NORMAL", "HARD"]
    let roadW: CGFloat = 1000
    let laps = 3

    let input = DuoInput()
    var phase = Phase.setup
    var phaseT: Double = 0
    var vsFriend = false
    var trackIdx = 0
    var sound = false
    var audio: RaceAudio?
    var focus = 4
    var focusX: CGFloat = 0
    var carPick = [6, 0]
    var pov = [0, 0]
    var ready = [false, false]
    var carChangedAt: [Double] = [0, 0]
    var difficulty = 1
    var demo = false
    var track = RaceTrack(RaceTheme.all[0])
    var racers: [Racer] = []
    var humanIdx: [Int] = []
    var bgOffset: [CGFloat] = [0, 0]
    var camX: [CGFloat] = [0, 0]
    var shake: [CGFloat] = [0, 0]
    var lapToast: [(String, Double)?] = [nil, nil]
    var raceTime: Double = 0
    var countT: Double = 0
    var goAt: Double = 3.6
    var finishWait: Double?
    var lastLight = -1
    var particles: [Particle] = []
    var boardOrder: [Int: CGFloat] = [:]
    var setupRects: [CGRect] = []
    var garageRects: [[(String, CGRect)]] = [[], []]
    var touchHeld: [Set<String>] = [[], []]
    var touchOwners: [Int: (Int, String)] = [:]
    var width: CGFloat = 1004
    var clock: Double = 0

    var theme: RaceTheme { RaceTheme.all[trackIdx] }
    var x0: CGFloat { StripController.gameChromeWidth + 2 }

    public init() {}

    public func activate(_ ctx: ModeContext) {
        width = ctx.size.width
        input.width = width
        input.reset()
        touchHeld = [[], []]; touchOwners = [:]
        setPhase(.setup)
        demo = false
        sound = false          // sound always starts off; turn it on in the menu each time
        audio?.stop(); audio = nil
    }
    public func deactivate() { input.reset(); audio?.stop(); audio = nil; sound = false }

    /// `--snapshot race:demo`. WIDEFIVE_RACE_SCENE = setup | garage | friend | cockpit | hood | bots | countdown | results,
    /// WIDEFIVE_RACE_TRACK = 0…3 pick what gets rendered.
    public func startDemo() {
        let env = ProcessInfo.processInfo.environment
        let scene = env["WIDEFIVE_RACE_SCENE"] ?? "friend"
        trackIdx = min(RaceTheme.all.count - 1, Int(env["WIDEFIVE_RACE_TRACK"] ?? "") ?? 0)
        demo = true; vsFriend = scene != "bots"; carPick = [6, 1]
        pov = scene == "cockpit" ? [1, 1] : scene == "hood" ? [2, 2] : [0, 0]
        switch scene {
        case "setup": demo = false; setPhase(.setup)
        case "garage": demo = false; carPick = [0, 3]; ready = [false, true]; setPhase(.garage)
        case "countdown": startRace()
        default:
            startRace()
            setPhase(.race)
            let offs: [CGFloat] = scene == "bots" ? [9000, 9900, 10800, 8200, 11600, 10400] : [10200, 9600, 8900, 10900, 9300]
            for i in racers.indices {
                racers[i].speed = racers[i].spec.top * 0.86
                racers[i].d = offs[i % offs.count] + 400
            }
            if scene == "bots", let h = humanIdx.first { racers[h].d = 10400; racers[h].x = -0.15 }
            if scene == "results" {
                for (k, i) in racers.indices.shuffled().enumerated() { racers[i].finished = 63.4 + Double(k) * 1.37 + Double(i) * 0.11; racers[i].bestLap = 20.2 + Double(k) * 0.4 }
                setPhase(.results)
                spawnConfetti(view: -1, count: 120)
            }
        }
    }

    func setPhase(_ p: Phase) { phase = p; phaseT = 0; input.clearEdges() }

    // MARK: race setup

    func startRace() {
        track = RaceTrack(theme)
        let humans = vsFriend ? 2 : 1
        let bots = vsFriend ? 3 : 5
        let names = ["VERSA", "NORRIS", "LECLERC", "ALONSO", "PIASTRI"].shuffled()
        let base: CGFloat = [0.84, 0.9, 0.96][difficulty]
        racers = []
        let total = humans + bots
        for slot in 0..<total {
            let row = slot / 2
            let x: CGFloat = slot % 2 == 0 ? -0.42 : 0.42
            let d = -CGFloat(row) * 700 - 300 - (slot % 2 == 0 ? 0 : 280)
            if slot < bots {
                let car = Int(RK.hash(slot * 31 + trackIdx) * CGFloat(RaceCar.all.count)) % RaceCar.all.count
                let paints = RaceCar.all[car].paints
                racers.append(Racer(car: car, paint: paints[1 + slot % (paints.count - 1)], d: d, x: x, human: nil, name: names[slot],
                                    skill: base + CGFloat.random(in: 0...0.04), lane: x))
            } else {
                let h = slot - bots
                racers.append(Racer(car: carPick[h], paint: RaceCar.all[carPick[h]].color, d: d, x: x, human: h, name: "P\(h + 1)", skill: 0.95, lane: x))
            }
        }
        humanIdx = (0..<humans).map { h in racers.firstIndex { $0.human == h }! }
        for (p, i) in humanIdx.enumerated() { camX[p] = racers[i].x }
        bgOffset = [0, 0]; shake = [0, 0]; lapToast = [nil, nil]
        raceTime = 0; countT = 0; lastLight = -1
        goAt = 3.25 + Double(RK.hash(Int(Date().timeIntervalSince1970)) * 0.7)
        finishWait = nil
        particles = []
        boardOrder = [:]
        setPhase(.countdown)
    }

    func held(_ p: Int, _ b: String) -> Bool {
        if vsFriend { return input.isDown(p, b) || touchHeld[p].contains(b) }
        return input.isDown(0, b) || input.isDown(1, b) || touchHeld[0].contains(b) || touchHeld[1].contains(b)
    }

    // MARK: update

    public func update(dt: Double) {
        let d = CGFloat(min(dt, 1.0 / 20))
        phaseT += dt
        clock += dt
        focusX = RK.approach(focusX, CGFloat(focus), 18, d)
        updateParticles(d)
        switch phase {
        case .setup:
            if phaseT < 0.02 { focusX = CGFloat(focus) }
            for p in 0..<2 {
                if input.take(p, "L") { focus = max(0, focus - 1) }
                if input.take(p, "R") { focus = min(4, focus + 1) }
                if input.take(p, "D"), focus == 2 { trackIdx = (trackIdx + RaceTheme.all.count - 1) % RaceTheme.all.count }
                if input.take(p, "F") || input.take(p, "U") { pickSetup(focus) }
            }
        case .garage:
            let n = RaceCar.all.count
            for p in 0..<2 {
                let pl = vsFriend ? p : 0
                if input.take(p, "S"), !vsFriend { difficulty = (difficulty + 1) % 3 }
                if ready[pl] { if input.take(p, "F") { ready[pl] = false }; continue }
                if input.take(p, "L") { carPick[pl] = (carPick[pl] + n - 1) % n; carChangedAt[pl] = clock }
                if input.take(p, "R") { carPick[pl] = (carPick[pl] + 1) % n; carChangedAt[pl] = clock }
                if input.take(p, "U") || input.take(p, "D") { pov[pl] = (pov[pl] + 1) % 3 }
                if input.take(p, "F") { ready[pl] = true }
            }
            if vsFriend ? (ready[0] && ready[1]) : ready[0] { startRace() }
        case .countdown:
            countT += dt
            let lights = min(5, Int(countT / 0.6))
            if lights != lastLight { lastLight = lights; if sound, lights > 0 { audio?.beep(false) } }
            for i in racers.indices { racers[i].wheel += 0; racers[i].steer = 0 }
            if countT >= goAt { if sound { audio?.beep(true) }; setPhase(.race) }
            updateAudio()
        case .race:
            raceTime += dt
            for i in racers.indices { stepRacer(i, d) }
            collide()
            if finishWait == nil, humanIdx.allSatisfy({ racers[$0].finished != nil }) { finishWait = 2.8 }
            if let w = finishWait {
                finishWait = w - dt
                if w - dt <= 0 { setPhase(.results); audio?.silence(); spawnConfetti(view: -1, count: 90) }
            }
            updateAudio()
        case .results:
            if phaseT > 0.8, input.take(0, "F") || input.take(1, "F") || input.take(0, "U") || input.take(1, "U") { setPhase(.setup) }
            if demo, phaseT > 6 { startDemo() }
        }
    }

    func pickSetup(_ i: Int) {
        focus = i
        switch i {
        case 0: vsFriend = false
        case 1: vsFriend = true
        case 2: trackIdx = (trackIdx + 1) % RaceTheme.all.count
        case 3:
            sound.toggle()
            if sound { if audio == nil { audio = RaceAudio() }; audio?.start() } else { audio?.stop(); audio = nil }
        default:
            ready = [false, false]
            setPhase(.garage)
        }
    }

    func stepRacer(_ i: Int, _ d: CGFloat) {
        var r = racers[i]
        let spec = r.spec
        let s = track.seg(r.d)
        var gas = false, brake = false, steer: CGFloat = 0, wantNitro = false
        if let p = r.human, !demo {
            steer = (held(p, "R") ? 1 : 0) - (held(p, "L") ? 1 : 0)
            brake = held(p, "D")
            gas = held(p, "U") || (!input.usedKeyboard && !brake)
            wantNitro = held(p, "F")
        } else {
            for (j, o) in racers.enumerated() where j != i {
                let rel = o.d - r.d
                if rel > 0, rel < 1100, abs(o.x - r.x) < 0.5 { r.lane = o.x > 0 ? max(-0.75, o.x - 0.7) : min(0.75, o.x + 0.7) }
            }
            let ahead = track.seg(r.d + 1600)
            let target = r.lane - (s.curve + ahead.curve) * 0.12
            steer = max(-1, min(1, (target - r.x) * 3))
            let want = spec.top * r.skill * (1 - min(0.3, max(abs(s.curve), abs(ahead.curve)) * 0.09))
            gas = r.speed < want
            brake = r.speed > want * 1.08
            wantNitro = r.nitro > 0.6 && abs(ahead.curve) < 0.25 && r.skill > 0.88
        }
        r.boosting = wantNitro && r.nitro > 0.02 && gas
        r.nitro = r.boosting ? r.nitro - 0.45 * d : min(1, r.nitro + 0.07 * d)
        let topNow = spec.top * (r.boosting ? 1.22 : 1)
        let offroad = abs(r.x) > (s.kerb ? 1.18 : 1.08)
        let cap = offroad ? spec.top * spec.offroad : topNow
        if gas { r.speed += spec.accel * (r.boosting ? 1.6 : 1) * max(0.05, 1 - 0.55 * r.speed / topNow) * d } else if brake { r.speed -= 14000 * d } else { r.speed -= 2500 * d }
        if r.speed > cap { r.speed = max(cap, r.speed - (offroad ? 2.5 : 1.2) * spec.accel * d) }
        r.speed = max(0, r.speed)
        let pct = r.speed / spec.top
        r.steer = RK.approach(r.steer, steer, 10, d)
        r.x += r.steer * d * spec.handling * 0.6 * min(1, r.speed / 2500)
        r.x -= d * pct * s.curve * 0.5
        let wallX = min(s.wallL.map { $0.x - 0.3 } ?? 2.6, s.wallR.map { $0.x - 0.3 } ?? 2.6)
        if abs(r.x) > wallX { r.x = wallX * (r.x > 0 ? 1 : -1); r.speed *= 1 - 1.5 * d }
        r.braking = brake
        r.wing = RK.approach(r.wing, (pct > 0.7 || brake) ? 1 : 0, 3, d)
        r.wheel += r.speed * d / 90
        r.d += r.speed * d
        let lap = Int(max(0, r.d) / track.length)
        if lap > r.lap {
            let t = raceTime - r.lapStart
            r.lastLap = t; r.bestLap = min(r.bestLap ?? t, t); r.lapStart = raceTime; r.lap = lap
            if let p = r.human, lap < laps { lapToast[p] = ("LAP \(lap + 1)/\(laps)  ·  \(RK.time(t))", clock) }
        }
        if r.finished == nil, r.d >= CGFloat(laps) * track.length {
            r.finished = raceTime
            if let p = r.human { lapToast[p] = ("FINISHED  \(RK.ordinal((ranking().firstIndex(of: i) ?? 0) + 1))", clock); spawnConfetti(view: p, count: 70) }
        }
        if let p = r.human {
            camX[p] = RK.approach(camX[p], pov[p] == 0 ? r.x * 0.8 : r.x, pov[p] == 0 ? 6 : 40, d)
            bgOffset[p] += s.curve * pct * d * 40
            let kerb = abs(r.x) > 1.0 && abs(r.x) < 1.2 && s.kerb
            let target: CGFloat = r.speed < 600 ? 0 : offroad ? 1 : kerb ? 0.45 : 0
            shake[p] = RK.approach(shake[p], target, 12, d)
        }
        racers[i] = r
    }

    func collide() {
        for i in racers.indices {
            for j in racers.indices where j > i {
                let dz = racers[j].d - racers[i].d
                guard abs(dz) < 300, abs(racers[i].x - racers[j].x) < 0.5 else { continue }
                let behind = dz > 0 ? i : j, ahead = dz > 0 ? j : i
                racers[behind].speed = min(racers[behind].speed, racers[ahead].speed * 0.93)
                racers[behind].x += racers[behind].x < racers[ahead].x ? -0.05 : 0.05
            }
        }
    }

    func ranking() -> [Int] {
        racers.indices.sorted { a, b in
            switch (racers[a].finished, racers[b].finished) {
            case let (fa?, fb?): return fa < fb
            case (.some, nil): return true
            case (nil, .some): return false
            default: return racers[a].d > racers[b].d
            }
        }
    }

    func updateAudio() {
        guard sound, let audio else { return }
        for v in 0..<2 {
            guard v < humanIdx.count else { audio.set(v, rpm: 0, on: false); continue }
            let r = racers[humanIdx[v]]
            let pct = Double(r.speed / r.spec.top)
            let gear = min(5, Int(pct * 6))
            audio.set(v, rpm: (pct * 6 - Double(gear)) * 0.8 + 0.3 + Double(gear) * 0.05, on: true)
        }
    }

    // MARK: particles

    func spawnConfetti(view: Int, count: Int) {
        let cols = [RCol.p1, RCol.p2, RCol.gold, RCol.go, RCol.white, RCol(0xff6b3d)]
        for k in 0..<count {
            let h = RK.hash(k * 13 + Int(clock * 100))
            particles.append(Particle(x: RK.hash(k * 7 + 1) , y: 1.05 + h * 0.4, vx: (RK.hash(k * 5 + 2) - 0.5) * 0.25, vy: -0.25 - h * 0.35,
                                      rot: h * 6, vr: (RK.hash(k * 3) - 0.5) * 14, life: 2.5 + h * 1.5, col: cols[k % cols.count], view: view))
        }
    }
    func updateParticles(_ d: CGFloat) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].x += particles[i].vx * d + sin(particles[i].rot) * 0.02 * d
            particles[i].y += particles[i].vy * d
            particles[i].rot += particles[i].vr * d
            particles[i].life -= d
        }
        particles.removeAll { $0.life <= 0 || $0.y < -0.2 }
    }

    // MARK: touch

    public func touchBegan(_ t: StripTouch) {
        switch phase {
        case .setup:
            guard let i = setupRects.firstIndex(where: { t.x >= $0.minX && t.x <= $0.maxX }) else { return }
            if i == 2, t.x < setupRects[2].midX { focus = 2; trackIdx = (trackIdx + RaceTheme.all.count - 1) % RaceTheme.all.count } else { pickSetup(i) }
        case .garage:
            garageTouch(t.x)
        case .results:
            if phaseT > 0.8 { setPhase(.setup) }
        default:
            let L = layout()
            for (p, v) in L.views.enumerated() where t.x >= v.minX && t.x <= v.maxX {
                let f = (t.x - v.minX) / v.width
                let b = f < 0.35 ? "L" : f > 0.65 ? "R" : "D"
                touchOwners[t.id] = (p, b); touchHeld[p].insert(b)
            }
            for (p, g) in L.gauges.enumerated() where t.x >= g.minX && t.x <= g.maxX { touchOwners[t.id] = (p, "F"); touchHeld[p].insert("F") }
        }
    }
    public func touchMoved(_ t: StripTouch) {
        guard let (p, b) = touchOwners[t.id], b != "F", p < layout().views.count else { return }
        let v = layout().views[p]
        let f = (t.x - v.minX) / v.width
        let nb = f < 0.35 ? "L" : f > 0.65 ? "R" : "D"
        if nb != b { touchHeld[p].remove(b); touchHeld[p].insert(nb); touchOwners[t.id] = (p, nb) }
    }
    public func touchEnded(_ t: StripTouch) {
        guard let (p, b) = touchOwners.removeValue(forKey: t.id) else { return }
        if !touchOwners.values.contains(where: { $0 == (p, b) }) { touchHeld[p].remove(b) }
    }
    public func touchCancelled(_ t: StripTouch) { touchEnded(t) }
    public func keyDown(_ key: GameKey) { input.key(key, down: true) }
    public func keyUp(_ key: GameKey) { input.key(key, down: false) }

    func garageTouch(_ x: CGFloat) {
        let n = RaceCar.all.count
        for p in 0..<2 {
            guard let hit = garageRects[p].first(where: { x >= $0.1.minX && x <= $0.1.maxX }) else { continue }
            switch hit.0 {
            case "prev": carPick[p] = (carPick[p] + n - 1) % n; ready[p] = false; carChangedAt[p] = clock
            case "next", "car": carPick[p] = (carPick[p] + 1) % n; ready[p] = false; carChangedAt[p] = clock
            case "pov": pov[p] = (pov[p] + 1) % 3
            case "ready": ready[p].toggle()
            case "ai": difficulty = (difficulty + 1) % 3
            default: break
            }
        }
        if vsFriend ? (ready[0] && ready[1]) : ready[0] { startRace() }
    }

    // MARK: layout + draw

    func layout() -> Layout {
        let left = x0, gw: CGFloat = 124, mw: CGFloat = 170, gap: CGFloat = 3
        let vw = floor((width - left - 2 * gw - mw - 4 * gap) / 2)
        let g1 = CGRect(x: left, y: 0, width: gw, height: 30)
        let v1 = CGRect(x: g1.maxX + gap, y: 0, width: vw, height: 30)
        let map = CGRect(x: v1.maxX + gap, y: 0, width: mw, height: 30)
        if vsFriend {
            let g2 = CGRect(x: width - gw, y: 0, width: gw, height: 30)
            let v2 = CGRect(x: map.maxX + gap, y: 0, width: g2.minX - gap - map.maxX - gap, height: 30)
            return Layout(gauges: [g1, g2], views: [v1, v2], map: map, board: nil)
        }
        return Layout(gauges: [g1], views: [v1], map: map, board: CGRect(x: map.maxX + gap, y: 0, width: width - map.maxX - gap, height: 30))
    }

    public func draw(_ c: Canvas) {
        width = c.width
        input.width = width
        input.players = vsFriend ? 2 : 1
        switch phase {
        case .setup: drawSetup(c)
        case .garage: drawGarage(c)
        case .countdown, .race: drawRace(c)
        case .results: drawRace(c); drawResults(c)
        }
        drawParticles(c, -1, c.bounds)
        drawWipe(c)
    }
}
