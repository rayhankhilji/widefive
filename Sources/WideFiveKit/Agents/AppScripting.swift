import AppKit
import ApplicationServices
import Carbon

/// AppleScript + Accessibility glue: list browser tabs, select a tab or terminal session, raise windows, read Dock badges.
/// Everything here only talks to apps that are already running, so nothing ever gets launched by a scan.
public enum AppScripting {
    public struct Tab: Equatable {
        public var bundleId: String
        public var window: Int
        public var index: Int
        public var url: String
        public var title: String
    }

    private static let unit = "\u{1F}"   // field separator in script output
    private static let line = "\u{1E}"   // record separator

    static func isRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Last AppleScript failure per target app (code, message), so the bar can say *why* tabs are missing.
    public private(set) static var lastErrors: [String: (code: Int, message: String)] = [:]
    private static let errorLock = NSLock()

    /// Apps macOS refused to let widefive script (System Settings → Privacy & Security → Automation).
    public static var automationDenied: [String] {
        errorLock.lock(); defer { errorLock.unlock() }
        return lastErrors.filter { $0.value.code == -1743 }.map { $0.key }.sorted()
    }

    // MARK: Automation permission (never block on it)

    public enum Permission: Equatable { case granted, denied, needsConsent, notRunning, unknown(Int32) }

    /// Asks macOS whether widefive may send Apple Events to an app, without ever showing a prompt or waiting.
    /// A scan only talks to apps that answer `.granted`; an unanswered consent prompt would otherwise stall it for 2 min.
    public static func permission(_ bundleId: String) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let desc = target.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .needsConsent
        case OSStatus(procNotFound): return .notRunning
        default: return .unknown(status)
        }
    }

    private static let consentQueue = DispatchQueue(label: "widefive.automation-consent")
    private static var consentAsked: Set<String> = []

    /// Shows macOS's "widefive wants to control …" prompt once per app per launch, on its own thread.
    public static func requestPermission(_ bundleId: String) {
        errorLock.lock()
        let first = consentAsked.insert(bundleId).inserted
        errorLock.unlock()
        guard first else { return }
        consentQueue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
            guard let desc = target.aeDesc else { return }
            let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
            errorLock.lock()
            if status == OSStatus(errAEEventNotPermitted) { lastErrors[bundleId] = (-1743, "Not authorized to send Apple events") }
            else if status == noErr { lastErrors[bundleId] = nil }
            errorLock.unlock()
        }
    }

    /// Wraps a script so no single Apple Event can hold a scan for more than `seconds`.
    static func timeBoxed(_ source: String, seconds: Int) -> String {
        "with timeout of \(seconds) seconds\n\(source)\nend timeout"
    }

    @discardableResult
    static func run(_ source: String, target: String = "") -> String? {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&err)
        errorLock.lock(); defer { errorLock.unlock() }
        if let err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "?"
            lastErrors[target] = (code, msg)
            NSLog("widefive: AppleScript \(target) failed (\(code)): \(msg)")
            return nil
        }
        lastErrors[target] = nil
        return result.stringValue ?? ""
    }

    /// Opens a Terminal window running `command` (for sessions with no window of their own). No Apple Events involved:
    /// a .command file is opened like a double-click.
    public static func openCommand(_ command: String, cwd: String?) -> Bool {
        let dir = ConfigStore.directory.appendingPathComponent("run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("open-\(abs(command.hashValue)).command")
        let cd = cwd.map { "cd \(quotedShell($0)) 2>/dev/null\n" } ?? ""
        let body = "#!/bin/zsh -l\n\(cd)exec \(command)\n"
        do {
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch { return false }
        return NSWorkspace.shared.open(file)
    }

    static func quotedShell(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: Browser tabs

    /// Every tab of every running supported browser. Safari and the Chromium family use different verbs.
    public static func browserTabs() -> [Tab] {
        var out: [Tab] = []
        for b in AgentCatalog.browsers where isRunning(b.bundleId) {
            switch permission(b.bundleId) {
            case .granted: break
            case .needsConsent:
                requestPermission(b.bundleId)
                continue
            case .denied:
                errorLock.lock(); lastErrors[b.bundleId] = (-1743, "Not authorized to send Apple events"); errorLock.unlock()
                continue
            case .notRunning:
                continue
            case .unknown:
                break // older macOS / odd state: try, but time-boxed
            }
            let titleOf = b.safari ? "name of t" : "title of t"
            let src = """
            tell application id \(quoted(b.bundleId))
                set u to character id 31
                set l to character id 30
                set out to ""
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set ti to 0
                    try
                        repeat with t in tabs of w
                            set ti to ti + 1
                            set theURL to ""
                            set theTitle to ""
                            try
                                set theURL to (URL of t) as text
                            end try
                            try
                                set theTitle to (\(titleOf)) as text
                            end try
                            set out to out & (wi as text) & u & (ti as text) & u & theURL & u & theTitle & l
                        end repeat
                    end try
                end repeat
                return out
            end tell
            """
            guard let text = run(timeBoxed(src, seconds: 3), target: b.bundleId), !text.isEmpty else { continue }
            for rec in text.components(separatedBy: line) {
                let f = rec.components(separatedBy: unit)
                guard f.count >= 4, let w = Int(f[0]), let i = Int(f[1]) else { continue }
                out.append(Tab(bundleId: b.bundleId, window: w, index: i, url: f[2], title: f[3]))
            }
        }
        return out
    }

    /// Selects the tab showing `url` (first match), raises its window and activates the browser.
    public static func focusTab(bundleId: String, url: String, title: String) -> Bool {
        let safari = AgentCatalog.browsers.first { $0.bundleId == bundleId }?.safari ?? false
        let select = safari ? "set current tab of w to t" : "set active tab index of w to ti"
        let unminimize = safari ? "set miniaturized of w to false" : "set minimized of w to false"
        let src = """
        tell application id \(quoted(bundleId))
            repeat with w in windows
                set ti to 0
                try
                    repeat with t in tabs of w
                        set ti to ti + 1
                        if (URL of t) is \(quoted(url)) then
                            \(select)
                            try
                                \(unminimize)
                            end try
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end try
            end repeat
            return ""
        end tell
        """
        if permission(bundleId) == .needsConsent { requestPermission(bundleId) }
        guard run(timeBoxed(src, seconds: 5), target: bundleId) == "ok" else {
            activate(bundleId)
            return false
        }
        // `set index … to 1` doesn't always pull a window from another Space; an AX raise does.
        raiseWindow(bundleId: bundleId, titleContaining: title)
        return true
    }

    // MARK: Terminal sessions

    /// Selects the Terminal.app / iTerm2 tab whose session runs on `tty` ("ttys003"); other hosts are just activated.
    /// Without a known host (tmux, ssh, launchd), every running tab-capable terminal is searched.
    public static func focusTerminal(bundleId: String?, tty: String?, window: String?) -> Bool {
        let hosts: [String]
        if let bundleId { hosts = [bundleId] } else { hosts = AgentCatalog.terminalHosts.filter { $0.value.tabs }.map { $0.key }.filter(isRunning) }
        for host in hosts where tty != nil && AgentCatalog.terminalHosts[host]?.tabs == true {
            if selectTerminalTab(bundleId: host, tty: tty!) {
                raiseWindow(bundleId: host, titleContaining: window)
                return true
            }
        }
        guard let host = hosts.first else { return false }
        activate(host)
        raiseWindow(bundleId: host, titleContaining: window)
        return false
    }

    private static func selectTerminalTab(bundleId: String, tty: String) -> Bool {
        let dev = quoted("/dev/" + tty)
        let src: String
        if bundleId == "com.apple.Terminal" {
            src = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (tty of t) is \(dev) then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        } else {
            src = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (tty of s) is \(dev) then
                                tell s to select
                                tell t to select
                                set index of w to 1
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                return ""
            end tell
            """
        }
        if permission(bundleId) == .needsConsent { requestPermission(bundleId) }
        return run(timeBoxed(src, seconds: 5), target: bundleId) == "ok"
    }

    // MARK: Apps & windows

    public static func activate(_ bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
        if app.isHidden { app.unhide() }
        if #available(macOS 14.0, *) { app.activate() } else { app.activate(options: [.activateIgnoringOtherApps]) }
    }

    /// Raises the first window of the app whose title contains `needle` (needs Accessibility). No-op without a needle.
    @discardableResult
    public static func raiseWindow(bundleId: String, titleContaining needle: String?) -> Bool {
        guard let needle, !needle.isEmpty, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1.0)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        let n = needle.lowercased()
        for w in windows {
            var t: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success,
                  let title = t as? String, title.lowercased().contains(n) else { continue }
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            return true
        }
        return false
    }

    // MARK: Dock badges

    /// Badge text per Dock item (keyed by the item's title, e.g. "Claude" → "1"). Needs Accessibility; empty without it.
    public static func dockBadges() -> [String: String] {
        guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let ax = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return [:] }
        var out: [String: String] = [:]
        for child in children {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == (kAXListRole as String) else { continue }
            var items: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &items) == .success,
                  let list = items as? [AXUIElement] else { continue }
            for item in list {
                var title: CFTypeRef?, badge: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &badge)
                if let t = title as? String, let b = badge as? String, !b.isEmpty { out[t] = b }
            }
        }
        return out
    }
}
