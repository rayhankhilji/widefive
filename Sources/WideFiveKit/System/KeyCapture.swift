import AppKit

/// "Key lock": steals the game keys (arrows, Z/X, space, P) from macOS with a CGEvent tap so you can play
/// without any window focused, and gives them straight back when you toggle it off.
/// Everything else keeps working normally — ⌘-anything is never swallowed.
public final class KeyCapture {
    public static let shared = KeyCapture()

    public private(set) var active = false
    public var onKey: ((GameKey, Bool) -> Void)?
    public var onPause: (() -> Void)?
    public var onExit: (() -> Void)?
    public var onChange: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private init() {}

    private static let keyMap: [Int64: GameKey] = [
        123: .left, 124: .right, 126: .up, 125: .down,
        0: .p1Left, 2: .p1Right, 13: .p1Up, 1: .p1Down,  // a / d / w / s
        3: .p1Fire, 5: .p1Special,                       // f / g
        44: .p2Fire, 47: .p2Special,                     // / and .
        49: .jump,                                   // space
        6: .run, 7: .action,                         // z / x
        36: .action,                                 // return
    ]

    @discardableResult
    public func toggle() -> Bool {
        if active { stop() } else { start() }
        return active
    }

    @discardableResult
    public func start() -> Bool {
        guard !active else { return true }
        guard Keys.ensureAccessibility(prompt: true) else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask),
                                        callback: { _, type, event, refcon in
                                            guard let refcon else { return Unmanaged.passUnretained(event) }
                                            let me = Unmanaged<KeyCapture>.fromOpaque(refcon).takeUnretainedValue()
                                            return me.handle(type: type, event: event)
                                        },
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t; source = src; active = true
        onChange?(true)
        return true
    }

    public func stop() {
        guard active else { return }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil; active = false
        onChange?(false)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // Never eat a shortcut: only plain keypresses belong to the game.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return Unmanaged.passUnretained(event)
        }
        let down = type == .keyDown
        switch code {
        case 35: // p → pause
            if down { DispatchQueue.main.async { self.onPause?() } }
            return nil
        case 53: // esc → leave the game and release the keys
            if down { DispatchQueue.main.async { self.onExit?(); self.stop() } }
            return nil
        default:
            guard let key = Self.keyMap[code] else { return Unmanaged.passUnretained(event) }
            if !(down && event.getIntegerValueField(.keyboardEventAutorepeat) != 0) {
                DispatchQueue.main.async { self.onKey?(key, down) }
            }
            return nil
        }
    }
}
