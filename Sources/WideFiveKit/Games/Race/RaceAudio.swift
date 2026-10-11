import AppKit
import AVFoundation

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
                    let saw = ph * 2 - 1, sq: Double = ph < 0.5 ? 1 : -1
                    s += (saw * 0.45 + sq * 0.25 + sin(ph * 2 * .pi) * 0.5) * st.vol[v]
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
