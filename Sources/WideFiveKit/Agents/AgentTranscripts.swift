import Foundation

/// Exact, zero-setup "what is it doing" for agents that journal their sessions to disk as they go:
///  • Claude Code appends every turn to ~/.claude/projects/<cwd with / → ->/<session>.jsonl
///  • Codex CLI appends to ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
/// The last line tells us whether the agent just finished a turn (waiting for you), is waiting on a tool
/// (permission prompt or a running tool) or is mid-turn (working). Nothing is installed or configured.
public enum AgentTranscripts {
    public enum Phase: Equatable {
        /// Last entry is the user's prompt or a tool result: the model is thinking / streaming.
        case working
        /// Last entry is assistant text with no tool call: turn over, waiting for the next prompt.
        case turnDone
        /// Last entry is a tool call with no result yet: either the tool is running or it's a permission prompt.
        case toolPending(String)
        /// The agent explicitly asked for approval / input (Codex approval events).
        case needsApproval(String)
    }

    public struct Verdict: Equatable {
        public var phase: Phase
        /// When the last entry was written.
        public var at: Date
        /// Short title for the session (first prompt / summary), if any.
        public var title: String?
        /// Last assistant text, trimmed, for the "needs you" message.
        public var lastText: String?
        public var file: URL
    }

    public static var claudeProjects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    public static var codexSessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")

    /// Bytes read from the end of a transcript per scan. Turns are small; big tool outputs are what pushes this up.
    static let tailBytes = 256 * 1024

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    // MARK: Claude Code

    /// Folder names Claude Code may use for a cwd (it has used both "slashes only" and "every non-alphanumeric").
    public static func claudeProjectNames(for cwd: String) -> [String] {
        let slashes = cwd.replacingOccurrences(of: "/", with: "-")
        let all = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return slashes == all ? [slashes] : [all, slashes]
    }

    /// Transcript files for a cwd, newest first. `since` filters out sessions that ended before the process started.
    public static func claudeTranscripts(cwd: String, since: Date) -> [URL] {
        let fm = FileManager.default
        var out: [(URL, Date)] = []
        for name in claudeProjectNames(for: cwd) {
            let dir = claudeProjects.appendingPathComponent(name)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m >= since else { continue }
                out.append((f, m))
            }
        }
        return out.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    public static func claudeVerdict(file: URL) -> Verdict? {
        guard let lines = tailLines(file) else { return nil }
        return claudeVerdict(lines: lines, file: file)
    }

    public static func claudeVerdict(lines: [String], file: URL) -> Verdict? {
        var title: String?
        var lastText: String?
        var verdict: Verdict?
        for raw in lines.reversed() {
            guard let obj = json(raw), let type = obj["type"] as? String else { continue }
            if type == "summary", title == nil, let s = obj["summary"] as? String { title = s; continue }
            guard type == "user" || type == "assistant" else { continue }
            if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true { continue }
            let msg = obj["message"] as? [String: Any] ?? [:]
            let when = date(obj["timestamp"]) ?? Date()
            if type == "user" {
                if title == nil, let s = msg["content"] as? String, !s.hasPrefix("<") { title = String(s.prefix(80)) }
                if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file) }
                // Keep scanning backwards only for the title.
                if title != nil { break } else { continue }
            }
            // assistant
            let blocks = msg["content"] as? [[String: Any]] ?? []
            if lastText == nil, let t = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lastText = String(trimmed.prefix(140)) }
            }
            if verdict == nil {
                if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" })?["name"] as? String {
                    verdict = Verdict(phase: .toolPending(tool), at: when, title: nil, lastText: nil, file: file)
                } else {
                    verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file)
                }
            }
            if title != nil, lastText != nil { break }
        }
        guard var v = verdict else { return nil }
        v.title = title
        v.lastText = lastText
        return v
    }

    // MARK: Codex CLI

    /// Rollout files modified since `since`, newest first, searched in the day folders from `since` to today.
    public static func codexTranscripts(since: Date) -> [URL] {
        let fm = FileManager.default
        var out: [(URL, Date)] = []
        let cal = Calendar(identifier: .gregorian)
        var day = cal.startOfDay(for: since.addingTimeInterval(-86400))
        let end = Date()
        var folders: [URL] = []
        while day <= end, folders.count < 400 {
            let c = cal.dateComponents([.year, .month, .day], from: day)
            folders.append(codexSessions.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)))
            day = cal.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1)
        }
        for dir in folders {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for f in files where f.pathExtension == "jsonl" && f.lastPathComponent.hasPrefix("rollout-") {
                guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m >= since else { continue }
                out.append((f, m))
            }
        }
        return out.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// The cwd recorded in a rollout's first line (session_meta, or the legacy flat header).
    public static func codexCwd(file: URL) -> String? {
        guard let h = FileHandle(forReadingAtPath: file.path) else { return nil }
        defer { try? h.close() }
        let data = h.readData(ofLength: 16 * 1024)
        guard let first = String(data: data, encoding: .utf8)?.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        return codexCwd(firstLine: String(first))
    }

    public static func codexCwd(firstLine: String) -> String? {
        guard let obj = json(firstLine) else { return nil }
        if let p = obj["payload"] as? [String: Any], let c = p["cwd"] as? String { return c }
        return obj["cwd"] as? String
    }

    public static func codexVerdict(file: URL) -> Verdict? {
        guard let lines = tailLines(file) else { return nil }
        return codexVerdict(lines: lines, file: file)
    }

    public static func codexVerdict(lines: [String], file: URL) -> Verdict? {
        var title: String?
        var lastText: String?
        var verdict: Verdict?
        var pendingCall: String?
        var sawOutput: Set<String> = []
        for raw in lines.reversed() {
            guard let obj = json(raw), let type = obj["type"] as? String, let p = obj["payload"] as? [String: Any] else { continue }
            let when = date(obj["timestamp"]) ?? Date()
            let kind = p["type"] as? String ?? ""
            if type == "event_msg" {
                switch kind {
                case "task_complete", "turn_complete":
                    if lastText == nil, let m = p["last_agent_message"] as? String { lastText = clean(m) }
                    if verdict == nil { verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file) }
                case "turn_aborted":
                    if verdict == nil { verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: "Turn aborted", file: file) }
                case "exec_approval_request", "apply_patch_approval_request", "request_user_input", "request_permissions", "elicitation_request":
                    if verdict == nil { verdict = Verdict(phase: .needsApproval(kind.replacingOccurrences(of: "_", with: " ")), at: when, title: nil, lastText: nil, file: file) }
                case "task_started", "turn_started":
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file) }
                case "user_message":
                    if let m = p["message"] as? String, title == nil { title = String(clean(m).prefix(80)) }
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file) }
                case "agent_message":
                    if lastText == nil, let m = p["message"] as? String { lastText = clean(m) }
                default: break
                }
            } else if type == "response_item" {
                switch kind {
                case "function_call_output", "custom_tool_call_output":
                    if let id = p["call_id"] as? String { sawOutput.insert(id) }
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file) }
                case "function_call", "custom_tool_call":
                    if verdict == nil, pendingCall == nil, let id = p["call_id"] as? String, !sawOutput.contains(id) {
                        pendingCall = p["name"] as? String ?? "tool"
                        verdict = Verdict(phase: .toolPending(pendingCall!), at: when, title: nil, lastText: nil, file: file)
                    }
                case "message":
                    let role = p["role"] as? String ?? ""
                    let text = ((p["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
                    if role == "user", title == nil, !text.isEmpty, !text.hasPrefix("<") { title = String(clean(text).prefix(80)) }
                    if role == "assistant", lastText == nil, !text.isEmpty { lastText = clean(text) }
                    if verdict == nil { verdict = Verdict(phase: role == "assistant" ? .turnDone : .working, at: when, title: nil, lastText: nil, file: file) }
                default: break
                }
            }
            if verdict != nil, title != nil, lastText != nil { break }
        }
        guard var v = verdict else { return nil }
        v.title = title
        v.lastText = lastText
        return v
    }

    // MARK: Helpers

    static func clean(_ s: String) -> String {
        String(s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
    }

    static func json(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8), !d.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// The last complete lines of a file (the final line may be mid-write and is dropped when it doesn't parse).
    public static func tailLines(_ file: URL, bytes: Int = tailBytes) -> [String]? {
        guard let h = FileHandle(forReadingAtPath: file.path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: start)
        let data = h.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
