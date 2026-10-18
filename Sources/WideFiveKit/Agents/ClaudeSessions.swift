import Foundation

/// Claude Code's own live status for every running session on this Mac. Each interactive or background session
/// (any terminal, the VS Code / Cursor / JetBrains extensions, the desktop app's local Code tab) keeps
/// ~/.claude/sessions/<pid>.json up to date with `status`: "busy" while a turn runs, "waiting" while it is blocked on
/// you (`waitingFor` says why: "input needed", a permission prompt…), "idle" once the turn is over. It is the same
/// file `claude agents` reads, so it is exact, instant and needs no setup.
public enum ClaudeSessions {
    public struct Entry: Equatable {
        public var pid: pid_t
        public var sessionId: String?
        public var cwd: String?
        /// "interactive", "bg", "daemon", "daemon-worker".
        public var kind: String?
        /// Who started it: "cli", "claude-vscode", "claude-desktop", "remote"…
        public var entrypoint: String?
        public var name: String?
        public var nameIsUser: Bool
        /// "busy", "waiting", "idle", "shell".
        public var status: String
        public var waitingFor: String?
        public var startedAt: Date?
        public var statusUpdatedAt: Date?
        /// Set when Remote Control is on: the claude.ai/code session mirroring this one.
        public var bridgeSessionId: String?
    }

    public static var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    /// Every live session (files of exited processes are skipped; Claude Code cleans them up itself).
    public static func entries() -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var out: [Entry] = []
        for n in names where n.hasSuffix(".json") {
            guard let data = fm.contents(atPath: directory.appendingPathComponent(n).path), let e = parse(data) else { continue }
            guard ProcessScanner.isAlive(e.pid) else { continue }
            out.append(e)
        }
        return out
    }

    public static func parse(_ data: Data) -> Entry? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let pid: pid_t
        if let p = o["pid"] as? Int { pid = pid_t(p) } else if let p = o["pid"] as? String, let i = Int32(p) { pid = i } else { return nil }
        func date(_ k: String) -> Date? {
            guard let ms = o[k] as? Double, ms > 0 else { return nil }
            return Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms)
        }
        let src = o["nameSource"] as? String
        return Entry(pid: pid, sessionId: o["sessionId"] as? String, cwd: o["cwd"] as? String, kind: o["kind"] as? String,
                     entrypoint: o["entrypoint"] as? String, name: o["name"] as? String, nameIsUser: src == "user" || src == "peer",
                     status: (o["status"] as? String) ?? "idle", waitingFor: o["waitingFor"] as? String,
                     startedAt: date("startedAt"), statusUpdatedAt: date("statusUpdatedAt") ?? date("updatedAt"),
                     bridgeSessionId: o["bridgeSessionId"] as? String)
    }

    /// The bar's state for an entry, with the message to show.
    public static func state(of e: Entry) -> (Agent.State, String?) {
        switch e.status {
        case "busy", "shell":
            return (.working, nil)
        case "waiting":
            return (.waiting, waitingMessage(e.waitingFor))
        default:
            // "idle" right after launch means nothing has happened yet; later it means a turn just finished.
            if let s = e.startedAt, let u = e.statusUpdatedAt, u.timeIntervalSince(s) < 3 { return (.idle, nil) }
            return (.done, "Done — your turn")
        }
    }

    static func waitingMessage(_ w: String?) -> String {
        guard let w = w?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty else { return "Needs your input" }
        let l = w.lowercased()
        if l == "input needed" || l == "input" { return "Needs your input" }
        if l.contains("permission") || l.hasPrefix("allow") || l.hasPrefix("approve") { return "Waiting for your permission — \(w)" }
        return w.prefix(1).uppercased() + w.dropFirst()
    }
}
