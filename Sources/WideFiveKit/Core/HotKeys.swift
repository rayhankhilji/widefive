import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission required).
public final class HotKeys {
    public static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextId: UInt32 = 1
    private var installed = false

    public func register(_ combo: String, _ handler: @escaping () -> Void) {
        guard let c = Keys.parse(combo) else { return }
        installIfNeeded()
        var mods: UInt32 = 0
        if c.flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if c.flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        if c.flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if c.flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        let id = nextId
        nextId += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x5746_4956), id: id) // 'WFIV'
        if RegisterEventHotKey(UInt32(c.keyCode), mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
            handlers[id] = handler
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeys.shared.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
