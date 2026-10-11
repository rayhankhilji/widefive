import AppKit
import Carbon.HIToolbox

public final class ActionRunner {
    public var switchMode: (String) -> Void = { _ in }
    public var toast: (String) -> Void = { _ in }

    public init() {}

    public func run(_ a: Action) {
        if let m = a.mode { switchMode(m) }
        if let k = a.keys { Keys.sendChord(k) }
        if let t = a.type {
            Keys.type(t)
            if a.submit == true { Keys.send(keyCode: CGKeyCode(kVK_Return), flags: []) }
        }
        if let m = a.media { SystemControl.media(m) }
        if let u = a.url, let url = URL(string: u) { NSWorkspace.shared.open(url) }
        if let o = a.open { Self.openApp(o) }
        if let s = a.shell { runShell(s, show: a.showOutput ?? false) }
        if let s = a.applescript { runAppleScript(s, show: a.showOutput ?? false) }
    }

    static func openApp(_ idOrName: String) {
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: idOrName) {
            ws.openApplication(at: url, configuration: .init())
        } else if let url = ws.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(idOrName).app")) ?? Optional(URL(fileURLWithPath: "/Applications/\(idOrName).app")),
                  FileManager.default.fileExists(atPath: url.path) {
            ws.openApplication(at: url, configuration: .init())
        }
    }

    func runShell(_ cmd: String, show: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if show {
                    let line = out.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "  ⏎  ")
                    DispatchQueue.main.async { self?.toast(line.isEmpty ? "✓ exit \(p.terminationStatus)" : line) }
                }
            } catch {
                DispatchQueue.main.async { self?.toast("shell: \(error.localizedDescription)") }
            }
        }
    }

    func runAppleScript(_ src: String, show: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var err: NSDictionary?
            let result = NSAppleScript(source: src)?.executeAndReturnError(&err)
            DispatchQueue.main.async {
                if let err { self?.toast("AppleScript: \(err[NSAppleScript.errorMessage] ?? "error")") }
                else if show { self?.toast(result?.stringValue ?? "✓") }
            }
        }
    }
}

public enum Keys {
    public static let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
        "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave,
        "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete, "backspace": kVK_Delete,
        "escape": kVK_Escape, "esc": kVK_Escape, "fwddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    public struct Combo: Equatable {
        public var keyCode: Int
        public var flags: CGEventFlags
    }

    public static func parse(_ combo: String) -> Combo? {
        var flags: CGEventFlags = []
        var key: Int?
        for raw in combo.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            let p = raw.trimmingCharacters(in: .whitespaces)
            switch p {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "alt", "opt", "option", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            case "": key = codes["="] // "cmd++" edge-case
            default: key = codes[p]
            }
        }
        guard let key else { return nil }
        return Combo(keyCode: key, flags: flags)
    }

    /// "cmd+k, z" → two strokes.
    public static func sendChord(_ chord: String) {
        guard ensureAccessibility() else { return }
        let parts = chord.split(separator: ",").map { String($0) }
        for (i, part) in parts.enumerated() {
            guard let c = parse(part) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                send(keyCode: CGKeyCode(c.keyCode), flags: c.flags)
            }
        }
    }

    public static func send(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    public static func type(_ text: String) {
        guard ensureAccessibility() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.utf16 {
            var ch = scalar
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    @discardableResult
    public static func ensureAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
