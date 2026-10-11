import AppKit
import CoreAudio
import AudioToolbox

/// Volume, brightness and media keys. Brightness uses the private DisplayServices framework (built-in display only).
public enum SystemControl {
    // MARK: Volume (CoreAudio, no permissions needed)

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr ? id : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    public static var volume: Float {
        get {
            guard let dev = defaultOutputDevice() else { return 0 }
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var addr = volumeAddress
            return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : 0
        }
        set {
            guard let dev = defaultOutputDevice() else { return }
            var v = Float32(max(0, min(1, newValue)))
            var addr = volumeAddress
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if v > 0 { setMuted(false) }
        }
    }

    public static func setMuted(_ m: Bool) {
        guard let dev = defaultOutputDevice() else { return }
        var v: UInt32 = m ? 1 : 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }

    public static var isMuted: Bool {
        guard let dev = defaultOutputDevice() else { return false }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v)
        return v != 0
    }

    // MARK: Brightness (private DisplayServices)

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getB: GetBrightness? = displayServices.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
    private static let setB: SetBrightness? = displayServices.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }

    private static var builtinDisplay: UInt32 {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    public static var brightness: Float {
        get {
            var v: Float = 0
            _ = getB?(builtinDisplay, &v)
            return v
        }
        set { _ = setB?(builtinDisplay, max(0, min(1, newValue))) }
    }

    // MARK: Media keys

    private static let NX_KEYTYPE_SOUND_UP: Int32 = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    private static let NX_KEYTYPE_MUTE: Int32 = 7
    private static let NX_KEYTYPE_PLAY: Int32 = 16
    private static let NX_KEYTYPE_NEXT: Int32 = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32 = 18

    public static func media(_ name: String) {
        switch name.lowercased() {
        case "playpause", "play": postMediaKey(NX_KEYTYPE_PLAY)
        case "next": postMediaKey(NX_KEYTYPE_NEXT)
        case "prev", "previous": postMediaKey(NX_KEYTYPE_PREVIOUS)
        case "volup": volume = volume + 0.0625
        case "voldown": volume = volume - 0.0625
        case "mute": setMuted(!isMuted)
        case "brightup": brightness = brightness + 0.0625
        case "brightdown": brightness = brightness - 0.0625
        default: break
        }
    }

    public static func postMediaKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                        windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
