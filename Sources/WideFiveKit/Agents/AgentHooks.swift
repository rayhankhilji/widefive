import Foundation

/// Exact "needs you" signals from agents that support hooks. A tiny shell script (installed into Claude Code,
/// Codex CLI and Cursor on request) drops one JSON file per agent process into ~/.widefive/agents; the monitor reads them.
public enum AgentHooks {
    public static let directory = ConfigStore.directory.appendingPathComponent("agents")
    public static let script = ConfigStore.directory.appendingPathComponent("bin/widefive-agent-hook")

    public enum Kind: String, CaseIterable {
        case claude, codex, cursor
        public var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex CLI"
            case .cursor: return "Cursor"
            }
        }
        var settingsFile: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .claude: return home.appendingPathComponent(".claude/settings.json")
            case .codex: return home.appendingPathComponent(".codex/config.toml")
            case .cursor: return home.appendingPathComponent(".cursor/hooks.json")
            }
        }
    }

    /// One event as written by the hook script.
    public struct Event: Equatable {
        public var kind: String
        public var pid: pid_t
        public var tty: String?
        public var time: Date
        public var state: Agent.State
        public var message: String?
        public var cwd: String?
        public var sessionId: String?
        /// The hook asked us to forget this process (SessionEnd).
        public var ended: Bool
    }

    // MARK: Reading

    public static func events() -> [Event] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var out: [Event] = []
        for n in names where n.hasSuffix(".json") {
            let url = directory.appendingPathComponent(n)
            guard let data = try? Data(contentsOf: url), let e = parse(data) else { continue }
            if e.ended || !ProcessScanner.isAlive(e.pid) { try? fm.removeItem(at: url); continue }
            out.append(e)
        }
        return out
    }

    public static func parse(_ data: Data) -> Event? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = obj["kind"] as? String, let pid = obj["pid"] as? Int else { return nil }
        let time = Date(timeIntervalSince1970: (obj["time"] as? Double) ?? 0)
        var tty = obj["tty"] as? String
        if tty == "??" || tty == "" || tty == "-" { tty = nil }
        let ev = obj["event"] as? [String: Any] ?? [:]
        var state: Agent.State = .working
        var message: String?
        var ended = false
        let name = (ev["hook_event_name"] as? String ?? ev["type"] as? String ?? "").lowercased()
        switch kind {
        case "claude":
            switch name {
            case "notification":
                state = .waiting
                message = ev["message"] as? String
                if message == nil || message?.isEmpty == true {
                    switch ev["notification_type"] as? String {
                    case "permission_prompt": message = "Needs your permission"
                    case "idle_prompt": message = "Waiting for your next prompt"
                    case "elicitation_dialog": message = "Asking you a question"
                    default: message = "Needs you"
                    }
                }
            case "stop": state = .waiting; message = "Finished — waiting for your next prompt"
            case "sessionend": ended = true
            case "sessionstart": state = .idle
            default: state = .working
            }
        case "codex":
            if name == "agent-turn-complete" || name.isEmpty {
                state = .waiting
                let last = (ev["last-assistant-message"] as? String ?? ev["last_assistant_message"] as? String ?? "")
                    .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                message = last.isEmpty ? "Turn finished — waiting for you" : String(last.prefix(120))
            }
        case "cursor":
            if name == "stop" || ev["status"] != nil { state = .waiting; message = "Agent finished — waiting for you" }
            else if name == "beforesubmitprompt" { state = .working }
        default: break
        }
        var cwd = ev["cwd"] as? String
        if cwd == nil, let roots = ev["workspace_roots"] as? [String] { cwd = roots.first }
        let session = ev["session_id"] as? String ?? ev["conversation_id"] as? String ?? ev["thread-id"] as? String
        return Event(kind: kind, pid: pid_t(pid), tty: tty, time: time, state: state, message: message, cwd: cwd, sessionId: session, ended: ended)
    }

    // MARK: The hook script

    static let scriptSource = """
    #!/bin/sh
    # widefive agent hook — tells the Touch Bar when a coding agent is working or waiting for you.
    # Installed by widefive (menu → Coding Agents). Safe to delete; widefive then falls back to CPU heuristics.
    # Usage: widefive-agent-hook <claude|codex|cursor> [json]   (JSON also accepted on stdin)
    dir="$HOME/.widefive/agents"
    mkdir -p "$dir" 2>/dev/null
    kind="${1:-claude}"
    if [ -n "$2" ]; then input="$2"; else input="$(cat 2>/dev/null)"; fi
    case "$input" in "{"*) ;; *) input="null";; esac
    # The agent is the first non-shell ancestor of this script.
    p=$PPID
    n=0
    while [ "$n" -lt 8 ]; do
      c="$(ps -o comm= -p "$p" 2>/dev/null)"
      case "$c" in
        *sh|*/sh|*zsh|*bash|*dash|*fish|*ksh) p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; n=$((n+1)) ;;
        *) break ;;
      esac
      [ -z "$p" ] && exit 0
    done
    tty="$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
    now="$(date +%s)"
    tmp="$dir/.$kind-$p.$$"
    printf '{"kind":"%s","pid":%s,"tty":"%s","time":%s,"event":%s}\\n' "$kind" "$p" "$tty" "$now" "$input" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$kind-$p.json"
    exit 0

    """

    @discardableResult
    static func writeScript() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try scriptSource.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    // MARK: Installing

    public static func isInstalled(_ kind: Kind) -> Bool {
        guard let text = try? String(contentsOf: kind.settingsFile, encoding: .utf8) else { return false }
        return text.contains("widefive-agent-hook")
    }

    /// Adds the hook to the agent's own config, keeping everything else in the file. Returns a one-line summary.
    public static func install(_ kind: Kind) -> String {
        do {
            let path = try writeScript().path
            switch kind {
            case .claude: try installClaude(path)
            case .codex: return try installCodex(path)
            case .cursor: try installCursor(path)
            }
            return "✓ \(kind.title) hooks installed — restart running sessions to pick them up"
        } catch {
            return "⚠️ \(kind.title): \(error.localizedDescription)"
        }
    }

    public static func uninstall(_ kind: Kind) -> String {
        do {
            switch kind {
            case .claude: try uninstallClaude()
            case .codex: try uninstallCodex()
            case .cursor: try uninstallCursor()
            }
            return "✓ \(kind.title) hooks removed"
        } catch {
            return "⚠️ \(kind.title): \(error.localizedDescription)"
        }
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "widefive", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) isn't a JSON object"])
        }
        return obj
    }

    static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Claude Code: ~/.claude/settings.json → "hooks": { "Notification": [ { "hooks": [ { "type": "command", "command": … } ] } ], … }
    public static let claudeEvents = ["Notification", "Stop", "UserPromptSubmit", "PreToolUse", "SessionStart", "SessionEnd"]

    static func installClaude(_ path: String) throws {
        let file = Kind.claude.settingsFile
        var root = try readJSON(file)
        root = claudeSettings(adding: path, to: root)
        try writeJSON(root, to: file)
    }

    /// Pure merge, so it can be unit-tested.
    public static func claudeSettings(adding path: String, to root: [String: Any]) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\(path) claude"
        for event in claudeEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let present = groups.contains { g in
                ((g["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("widefive-agent-hook") == true }
            }
            if !present {
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 10]]])
                hooks[event] = groups
            }
        }
        root["hooks"] = hooks
        return root
    }

    public static func claudeSettings(removingFrom root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { g in
                var g = g
                let kept = ((g["hooks"] as? [[String: Any]]) ?? []).filter { ($0["command"] as? String)?.contains("widefive-agent-hook") != true }
                if kept.isEmpty, (g["hooks"] as? [[String: Any]])?.isEmpty == false { return nil }
                g["hooks"] = kept
                return g
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }

    static func uninstallClaude() throws {
        let file = Kind.claude.settingsFile
        let root = try readJSON(file)
        try writeJSON(claudeSettings(removingFrom: root), to: file)
    }

    /// Codex CLI: ~/.codex/config.toml → notify = ["…/widefive-agent-hook", "codex"] (top level, before any [table]).
    static func installCodex(_ path: String) throws -> String {
        let file = Kind.codex.settingsFile
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let (out, note) = codexConfig(adding: path, to: text)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: file, atomically: true, encoding: .utf8)
        return note
    }

    public static func codexConfig(adding path: String, to text: String) -> (String, String) {
        let line = "notify = [\"\(path)\", \"codex\"]"
        if text.contains("widefive-agent-hook") { return (text, "✓ Codex hook already installed") }
        let hasNotify = text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }
        if hasNotify {
            return (text, "⚠️ ~/.codex/config.toml already has a notify setting — point it at \(path) codex by hand")
        }
        let body = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
        return ("# widefive: tell the Touch Bar when a turn finishes\n\(line)\n" + body, "✓ Codex hook installed — restart codex to pick it up")
    }

    public static func codexConfig(removingFrom text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("widefive-agent-hook") && !$0.contains("# widefive: tell the Touch Bar") }
            .joined(separator: "\n")
    }

    static func uninstallCodex() throws {
        let file = Kind.codex.settingsFile
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        try codexConfig(removingFrom: text).write(to: file, atomically: true, encoding: .utf8)
    }

    /// Cursor: ~/.cursor/hooks.json → { "version": 1, "hooks": { "stop": [ { "command": … } ], "beforeSubmitPrompt": [ … ] } }
    public static let cursorEvents = ["stop", "beforeSubmitPrompt"]

    static func installCursor(_ path: String) throws {
        let file = Kind.cursor.settingsFile
        let root = try readJSON(file)
        try writeJSON(cursorHooks(adding: path, to: root), to: file)
    }

    public static func cursorHooks(adding path: String, to root: [String: Any]) -> [String: Any] {
        var root = root
        if root["version"] == nil { root["version"] = 1 }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in cursorEvents {
            var list = hooks[event] as? [[String: Any]] ?? []
            if !list.contains(where: { ($0["command"] as? String)?.contains("widefive-agent-hook") == true }) {
                list.append(["command": "\(path) cursor"])
                hooks[event] = list
            }
        }
        root["hooks"] = hooks
        return root
    }

    public static func cursorHooks(removingFrom root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let kept = list.filter { ($0["command"] as? String)?.contains("widefive-agent-hook") != true }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        root["hooks"] = hooks
        return root
    }

    static func uninstallCursor() throws {
        let file = Kind.cursor.settingsFile
        let root = try readJSON(file)
        try writeJSON(cursorHooks(removingFrom: root), to: file)
    }
}
