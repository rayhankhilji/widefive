import AppKit
import AVFoundation

/// Polyphonic synth across the whole strip. Chromatic "flat piano": white keys wide, black keys narrow, side by side
/// (the Touch Bar only senses horizontal position). Slide to glide. Right edge: waveform + octave buttons.
public final class PianoMode: StripMode {
    public let id = "piano"
    public let title = "Piano"
    public let icon = "pianokeys"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }
    public var allowsGestures: Bool { false }

    private let synth = Synth()
    private var keys: [(note: Int, rect: CGRect, black: Bool)] = []
    private var touchNotes: [Int: Int] = [:]
    private var lit: [Int: Double] = [:]
    private var octave = 4
    private var controlRects: [(String, CGRect)] = []
    private let waveNames = ["sine", "square", "saw", "tri"]
    private let presses = Presses<String>()

    public init() {}

    public func activate(_ ctx: ModeContext) { synth.start() }
    public func deactivate() { synth.allOff(); synth.stop() }

    private func layout(_ width: CGFloat) {
        let x0 = Metrics.contentX - 2
        let ctrlW: CGFloat = 3 * 36 + 10
        let usable = width - x0 - ctrlW
        let base = 12 * octave
        let notes = Array(base..<(base + 25))
        let units = notes.reduce(CGFloat(0)) { $0 + (Self.isBlack($1) ? 0.62 : 1) }
        let unit = usable / units
        var x = x0
        keys = notes.map { n in
            let w = (Self.isBlack(n) ? 0.62 : 1) * unit
            defer { x += w }
            return (n, CGRect(x: x, y: Self.isBlack(n) ? 7 : 1, width: w - 2, height: Self.isBlack(n) ? 22 : 28), Self.isBlack(n))
        }
        let cx = width - ctrlW + 8
        controlRects = [("wave", CGRect(x: cx, y: 1.5, width: 40, height: 27)),
                        ("down", CGRect(x: cx + 44, y: 1.5, width: 30, height: 27)),
                        ("up", CGRect(x: cx + 78, y: 1.5, width: 30, height: 27))]
    }

    static func isBlack(_ n: Int) -> Bool { [1, 3, 6, 8, 10].contains(n % 12) }
    static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    public func update(dt: Double) {
        presses.step(dt)
        for (k, v) in lit { lit[k] = v - dt * 2.2; if lit[k]! <= 0 { lit[k] = nil } }
        for n in touchNotes.values { lit[n] = 1 }
    }

    public func draw(_ c: Canvas) {
        layout(c.width)
        let theme = c.theme
        let rad = max(2, min(5, theme.radius * 0.6))
        for k in keys {
            let glow = CGFloat(lit[k.note] ?? 0)
            let litCol = theme.accent.mix(theme.accent2, CGFloat(k.note % 12) / 11)
            let r = k.rect
            if k.black {
                let base = theme.isLight ? NSColor(white: 0.18, alpha: 1) : theme.surfaceHi.mix(NSColor(white: 0.2, alpha: 1), 0.5)
                let f = base.mix(litCol, glow)
                c.glowing(litCol, blur: 8, strength: glow) { c.gradient(r, [f.mix(.white, 0.16), f.mix(.black, 0.3)], radius: rad) }
                c.roundRect(CGRect(x: r.minX + 1.5, y: r.maxY - 2.5, width: r.width - 3, height: 1), radius: 0.5, fill: NSColor(white: 1, alpha: 0.18))
            } else {
                let ivory = theme.isLight ? NSColor.white : NSColor(white: 0.94, alpha: 1)
                let f = ivory.mix(litCol, glow * 0.8)
                c.glowing(litCol, blur: 10, strength: glow) { c.gradient(r, [f, f.mix(NSColor(white: 0.72, alpha: 1), 0.35)], radius: rad) }
                c.roundRect(CGRect(x: r.minX + 1.5, y: r.minY + 1.5, width: r.width - 3, height: 2), radius: 1, fill: NSColor(white: 0, alpha: 0.07))
            }
            if k.note % 12 == 0 {
                c.text("C\(k.note / 12 - 1)", x: r.midX, y: 3, size: 7.5, color: glow > 0.3 ? .white : NSColor(white: 0.45, alpha: 1), weight: .bold, align: .center)
            }
        }
        for (name, r) in controlRects {
            c.button(r, style: name == "wave" ? .tinted(theme.accent2) : .plain, pressed: presses.amount(name)) { fg in
                switch name {
                case "wave":
                    c.caption(waveNames[synth.waveform], x: r.midX, y: 15.5, color: fg, align: .center)
                    waveGlyph(c, CGRect(x: r.minX + 9, y: r.minY + 5, width: r.width - 18, height: 6), fg)
                case "down": c.symbol("minus", in: r, color: fg, pointSize: 10)
                default: c.symbol("plus", in: r, color: fg, pointSize: 10)
                }
            }
        }
        let mid = (controlRects[1].1.maxX + controlRects[2].1.minX) / 2
        c.text("\(octave)", x: mid, y: 21.5, size: 6.5, color: theme.dim, weight: .bold, align: .center)
    }

    private func waveGlyph(_ c: Canvas, _ r: CGRect, _ col: NSColor) {
        let path = CGMutablePath()
        let steps = 24
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2
            let ph = t.truncatingRemainder(dividingBy: 1)
            let v: Double
            switch synth.waveform {
            case 0: v = sin(2 * .pi * t)
            case 1: v = ph < 0.5 ? 1 : -1
            case 2: v = 2 * ph - 1
            default: v = 1 - 4 * abs(ph - 0.5)
            }
            let p = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(steps), y: r.midY + CGFloat(v) * r.height / 2)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        c.cg.saveGState()
        c.cg.addPath(path)
        c.cg.setStrokeColor(col.cgColor)
        c.cg.setLineWidth(1.2)
        c.cg.setLineJoin(.round)
        c.cg.strokePath()
        c.cg.restoreGState()
    }

    private func note(at x: CGFloat) -> Int? { keys.first { x >= $0.rect.minX && x <= $0.rect.maxX + 1.5 }?.note }

    public func touchBegan(_ t: StripTouch) {
        if let (name, _) = controlRects.first(where: { $0.1.contains(CGPoint(x: t.x, y: 15)) }) {
            presses.press(name)
            switch name {
            case "wave": synth.waveform = (synth.waveform + 1) % waveNames.count
            case "down": octave = max(1, octave - 1)
            default: octave = min(7, octave + 1)
            }
            return
        }
        guard let n = note(at: t.x) else { return }
        touchNotes[t.id] = n
        synth.noteOn(n)
    }

    public func touchMoved(_ t: StripTouch) {
        guard let old = touchNotes[t.id], let n = note(at: t.x), n != old else { return }
        synth.noteOff(old)
        touchNotes[t.id] = n
        synth.noteOn(n)
    }

    public func touchEnded(_ t: StripTouch) {
        presses.releaseAll()
        if let n = touchNotes.removeValue(forKey: t.id) { synth.noteOff(n) }
    }
}

/// Minimal polyphonic synth on an AVAudioSourceNode.
final class Synth {
    struct Voice { var note: Int; var freq: Double; var phase: Double = 0; var env: Double = 0; var releasing = false }
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var voices: [Voice] = []
    private let lock = NSLock()
    var waveform = 1
    private var running = false

    func start() {
        guard !running else { return }
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        let sr = fmt.sampleRate > 0 ? fmt.sampleRate : 44100
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let n = AVAudioSourceNode(format: mono) { [unowned self] _, _, frameCount, abl -> OSStatus in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            guard let out = buf[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.lock.lock()
            let wave = self.waveform
            for f in 0..<Int(frameCount) {
                var s = 0.0
                for i in self.voices.indices {
                    var v = self.voices[i]
                    v.env = v.releasing ? v.env * 0.9993 : min(1, v.env + 0.004)
                    let p = v.phase
                    let osc: Double
                    switch wave {
                    case 0: osc = sin(2 * .pi * p)
                    case 1: osc = p < 0.5 ? 0.6 : -0.6
                    case 2: osc = (2 * p - 1) * 0.7
                    default: osc = 4 * abs(p - 0.5) - 1
                    }
                    s += osc * v.env * 0.18
                    v.phase += v.freq / sr
                    if v.phase >= 1 { v.phase -= 1 }
                    self.voices[i] = v
                }
                out[f] = Float(tanh(s))
            }
            self.voices.removeAll { $0.releasing && $0.env < 0.001 }
            self.lock.unlock()
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: mono)
        node = n
        do { try engine.start(); running = true } catch { NSLog("widefive synth: \(error)") }
    }

    func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
        running = false
    }

    func noteOn(_ n: Int) {
        lock.lock()
        voices.append(Voice(note: n, freq: 440 * pow(2, Double(n - 69) / 12)))
        if voices.count > 10 { voices.removeFirst() }
        lock.unlock()
    }

    func noteOff(_ n: Int) {
        lock.lock()
        for i in voices.indices where voices[i].note == n { voices[i].releasing = true }
        lock.unlock()
    }

    func allOff() {
        lock.lock(); for i in voices.indices { voices[i].releasing = true }; lock.unlock()
    }
}
