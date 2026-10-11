import AppKit
import IOKit

/// Keyboard backlight. Uses the private CoreBrightness `KeyboardBrightnessClient` where it exists and
/// falls back to the illumination media keys.
///
/// Note for Intel MacBook Pros: the backlight is a single zone driven by one LED controller, so the
/// brightness applies to every key. Per-key control is not possible in software on this hardware.
public enum KeyboardLight {
    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let framework = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

    private static let client: NSObject? = {
        _ = framework
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private static func imp<T>(_ name: String, as: T.Type) -> (T, Selector)? {
        guard let obj = client else { return nil }
        let sel = NSSelectorFromString(name)
        guard let m = class_getInstanceMethod(type(of: obj), sel) else { return nil }
        return (unsafeBitCast(method_getImplementation(m), to: T.self), sel)
    }

    public static var isAvailable: Bool { imp("brightnessForKeyboard:", as: GetFn.self) != nil }

    public static var brightness: Float {
        get {
            guard let obj = client, let (f, sel) = imp("brightnessForKeyboard:", as: GetFn.self) else { return 0 }
            return max(0, min(1, f(obj, sel, 1)))
        }
        set {
            let v = max(0, min(1, newValue))
            if let obj = client, let (f, sel) = imp("setBrightness:forKeyboard:", as: SetFn.self) {
                _ = f(obj, sel, v, 1)
            } else {
                step(up: v > brightness)
            }
        }
    }

    /// Fallback: tap the keyboard-illumination keys (F5/F6 on Intel MacBook Pros).
    public static func step(up: Bool) {
        post(up ? 21 : 22) // NX_KEYTYPE_ILLUMINATION_UP / _DOWN
    }

    public static func toggle() {
        if brightness > 0.01 { lastLevel = brightness; brightness = 0 } else { brightness = lastLevel }
    }

    private static var lastLevel: Float = 0.5

    private static func post(_ key: Int32) {
        for down in [true, false] {
            let data = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            guard let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00)),
                                             timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1),
                  let cg = e.cgEvent else { continue }
            cg.post(tap: .cghidEventTap)
        }
    }
}
