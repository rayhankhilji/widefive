import AppKit
import AVFoundation
import Accelerate

/// Live microphone spectrum (vDSP FFT). Tap to cycle styles. Falls back to an idle animation without mic access.
public final class VisualizerMode: StripMode {
    public let id = "visualizer"
    public let title = "Visualizer"
    public let icon = "waveform"
    public var isAnimated: Bool { true }
    public var showsExitButton: Bool { true }

    private let engine = AVAudioEngine()
    private var bands = [Float](repeating: 0, count: 96)
    private var peaks = [Float](repeating: 0, count: 96)
    private let lock = NSLock()
    private var running = false
    private var denied = false
    private var style = 0
    private let styles = ["bars", "mirror", "dots", "wave"]
    private var fft: vDSP.FFT<DSPSplitComplex>?
    private let n = 1024

    public init() {}

    public func activate(_ ctx: ModeContext) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { ok ? self.startEngine() : (self.denied = true) } }
        default: denied = true
        }
    }

    public func deactivate() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    private func startEngine() {
        guard !running else { return }
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self)
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { denied = true; return }
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(n), format: fmt) { [weak self] buf, _ in self?.process(buf) }
        do { try engine.start(); running = true } catch { denied = true }
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData?[0], Int(buf.frameLength) >= n, let fft else { return }
        var windowed = [Float](repeating: 0, count: n)
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        vDSP.multiply(UnsafeBufferPointer(start: ch, count: n), window, result: &windowed)
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &mags)
            }
        }
        // Log-spaced bands from ~40Hz to ~16kHz.
        let count = bands.count
        var newBands = [Float](repeating: 0, count: count)
        let lo = log2(2.0), hi = log2(Double(n / 2 - 1))
        for b in 0..<count {
            let a = Int(pow(2, lo + (hi - lo) * Double(b) / Double(count)))
            let e = max(a + 1, Int(pow(2, lo + (hi - lo) * Double(b + 1) / Double(count))))
            var m: Float = 0
            for i in a..<min(e, n / 2) { m = max(m, mags[i]) }
            newBands[b] = min(1, max(0, (20 * log10(m + 1e-6) + 10) / 50))
        }
        lock.lock()
        for i in 0..<count { bands[i] = max(newBands[i], bands[i] * 0.86) }
        lock.unlock()
    }

    public func update(dt: Double) {
        lock.lock()
        if !running {
            let t = CACurrentMediaTime()
            for i in bands.indices { bands[i] = Float(0.25 + 0.2 * sin(t * 2 + Double(i) * 0.25) * sin(t * 0.7 + Double(i) * 0.05)) }
        }
        for i in peaks.indices { peaks[i] = max(bands[i], peaks[i] - Float(dt) * 0.6) }
        lock.unlock()
    }

    public func draw(_ c: Canvas) {
        lock.lock(); let b = bands, p = peaks; lock.unlock()
        let x0 = StripController.exitWidth + 4
        let w = (c.width - x0) / CGFloat(b.count)
        let h = c.height
        for i in b.indices {
            let v = CGFloat(b[i])
            let x = x0 + CGFloat(i) * w
            let col = NSColor.hsb(CGFloat(i) / CGFloat(b.count) * 0.8 + CGFloat(c.time * 0.05), 0.9, 1)
            switch style {
            case 0:
                c.gradient(CGRect(x: x, y: 0, width: w - 1, height: max(1, v * h)), [col, col.withAlphaComponent(0.35)])
                c.fill(CGRect(x: x, y: CGFloat(p[i]) * h - 1, width: w - 1, height: 1), .white)
            case 1:
                let bh = max(1, v * h / 2)
                c.fill(CGRect(x: x, y: h / 2 - bh, width: w - 1, height: bh * 2), col)
            case 2:
                let dots = Int(v * 6)
                for d in 0..<dots { c.circle(center: CGPoint(x: x + w / 2, y: 2.5 + CGFloat(d) * 5), radius: min(2, w / 2.2), col) }
            default:
                if i > 0 {
                    let prev = CGFloat(b[i - 1])
                    c.line(from: CGPoint(x: x - w / 2, y: h / 2 + (prev - 0.3) * h * sin(CGFloat(i - 1) * 0.6 + CGFloat(c.time) * 4)),
                           to: CGPoint(x: x + w / 2, y: h / 2 + (v - 0.3) * h * sin(CGFloat(i) * 0.6 + CGFloat(c.time) * 4)), col, width: 1.5)
                }
            }
        }
        if denied {
            c.roundRect(CGRect(x: c.width / 2 - 190, y: 4, width: 380, height: 22), radius: 6, fill: NSColor(white: 0, alpha: 0.75))
            c.text("Mic access needed: System Settings › Privacy › Microphone", x: c.width / 2, size: 10, color: .white, align: .center)
        }
    }

    public func touchEnded(_ t: StripTouch) { if abs(t.dx) < 20 { style = (style + 1) % styles.count } }
}
