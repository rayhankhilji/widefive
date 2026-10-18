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
        /// What it is doing right now, in words: "Running swift test", "Editing AgentMonitor.swift", "Thinking".
        public var activity: String? = nil
        /// The last turn ended on a usage limit or an API error.
        public var problem: Problem? = nil
        /// Git branch the session is on, when the journal records it.
        public var branch: String? = nil
    }

    public enum Problem: Equatable {
        /// Usage / rate limit, with when it resets if the message says.
        case limited(resets: String?)
        case error(String)
    }

    /// "Claude AI usage limit reached|1760000000", "5-hour limit reached ∙ resets 3pm", "API Error: 429 …",
    /// "You've hit your usage limit. Try again in 2 hours." → limited; any other API error → error.
    public static func classifyProblem(_ text: String) -> Problem {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()
        let limited = l.contains("limit reached") || l.contains("usage limit") || l.contains("rate limit") || l.contains("rate_limit")
            || l.contains(" 429") || l.contains("quota") || l.contains("too many requests")
        guard limited else { return .error(String(t.replacingOccurrences(of: "\n", with: " ").prefix(100))) }
        if let bar = t.lastIndex(of: "|"), let epoch = Double(t[t.index(after: bar)...].trimmingCharacters(in: .whitespaces)), epoch > 1e9 {
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDateInToday(Date(timeIntervalSince1970: epoch)) ? "h:mm a" : "EEE h:mm a"
            return .limited(resets: "resets " + f.string(from: Date(timeIntervalSince1970: epoch)).lowercased())
        }
        if let r = l.range(of: "resets") ?? l.range(of: "try again in") {
            let tail = t[r.lowerBound...].split(whereSeparator: { ".\n(".contains($0) }).first.map(String.init) ?? ""
            return .limited(resets: tail.isEmpty ? nil : String(tail.prefix(28)))
        }
        return .limited(resets: nil)
    }

    /// A tool call in plain words: Bash → "swift test", Edit → "Editing Foo.swift", Grep → "Searching “foo”".
    public static func describeTool(_ name: String, input: [String: Any]) -> String {
        func file(_ k: String = "file_path") -> String? { (input[k] as? String).map { ($0 as NSString).lastPathComponent } }
        func short(_ s: String) -> String { String(s.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces).prefix(60) ?? "") }
        switch name {
        case "Bash", "exec_command", "shell", "local_shell", "container.exec":
            if let c = input["command"] as? String, !c.isEmpty { return "Running " + short(c) }
            if let c = input["cmd"] as? String, !c.isEmpty { return "Running " + short(c) }
            if let a = input["command"] as? [String] {
                let c = (a.count >= 3 && ["bash", "zsh", "sh"].contains(a[0]) && a[1].hasPrefix("-")) ? a[2] : a.joined(separator: " ")
                return "Running " + short(c)
            }
            return "Running a command"
        case "Edit", "MultiEdit", "str_replace_based_edit_tool": return "Editing " + (file() ?? "files")
        case "Write": return "Writing " + (file() ?? "a file")
        case "Read": return "Reading " + (file() ?? "a file")
        case "NotebookEdit": return "Editing " + (file("notebook_path") ?? "a notebook")
        case "Grep": return "Searching “\(short((input["pattern"] as? String) ?? ""))”"
        case "Glob": return "Finding \(short((input["pattern"] as? String) ?? "files"))"
        case "WebFetch": return "Fetching " + ((input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "a page")
        case "WebSearch", "web_search": return "Searching the web"
        case "Task", "Agent": return "Subagent: " + short((input["description"] as? String) ?? "working")
        case "TodoWrite": return "Planning"
        case "apply_patch": return "Editing files"
        case "update_plan": return "Planning"
        default:
            if name.hasPrefix("mcp__") { return "Using " + (name.components(separatedBy: "__").last ?? name).replacingOccurrences(of: "_", with: " ") }
            return "Using \(name)"
        }
    }

    public static var claudeProjects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    public static var codexSessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")

    /// Bytes read from the end of a transcript per scan. Turns are small; big tool outputs are what pushes this up.
    public static let tailBytes = 256 * 1024

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
    /// /tmp and /var are really /private/tmp and /private/var; the kernel reports one spelling and tools the other.
    public static func claudeProjectNames(for cwd: String) -> [String] {
        var paths = [cwd]
        if cwd.hasPrefix("/private/") { paths.append(String(cwd.dropFirst("/private".count))) }
        else if cwd.hasPrefix("/tmp") || cwd.hasPrefix("/var") || cwd.hasPrefix("/etc") { paths.append("/private" + cwd) }
        var out: [String] = []
        for p in paths {
            let all = String(p.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let slashes = p.replacingOccurrences(of: "/", with: "-")
            for n in [all, slashes] where !out.contains(n) { out.append(n) }
        }
        return out
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
        var summary: String?
        var prompt: String?
        var lastText: String?
        var branch: String?
        var verdict: Verdict?
        var scanned = 0
        for raw in lines.reversed() {
            scanned += 1
            if scanned > 400 { break }
            guard let obj = json(raw), let type = obj["type"] as? String else { continue }
            if type == "summary", summary == nil, let s = obj["summary"] as? String, !s.isEmpty { summary = s; continue }
            guard type == "user" || type == "assistant" else { continue }
            if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true { continue }
            if branch == nil, let b = obj["gitBranch"] as? String, !b.isEmpty, b != "HEAD" { branch = b }
            let msg = obj["message"] as? [String: Any] ?? [:]
            let when = date(obj["timestamp"]) ?? Date()
            let blocks = msg["content"] as? [[String: Any]] ?? []
            if type == "user" {
                if let s = msg["content"] as? String, !s.hasPrefix("<") { prompt = String(s.prefix(80)) }
                else if let t = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String, !t.hasPrefix("<") { prompt = String(t.prefix(80)) }
                if verdict == nil {
                    let isResult = blocks.contains { $0["type"] as? String == "tool_result" }
                    verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file, activity: isResult ? "Thinking" : "Thinking")
                }
                continue
            }
            // assistant
            let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String
            let apiError = obj["isApiErrorMessage"] as? Bool == true || obj["error"] != nil
            if lastText == nil, !apiError, let t = text {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lastText = String(trimmed.prefix(140)) }
            }
            if verdict == nil {
                if apiError {
                    let problem = classifyProblem(text ?? ((obj["error"] as? String) ?? "API error"))
                    verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file, problem: problem)
                } else if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }) {
                    let name = tool["name"] as? String ?? "tool"
                    verdict = Verdict(phase: .toolPending(name), at: when, title: nil, lastText: nil, file: file,
                                      activity: describeTool(name, input: tool["input"] as? [String: Any] ?? [:]))
                } else {
                    verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file)
                }
            }
        }
        guard var v = verdict else { return nil }
        v.title = summary ?? prompt
        v.lastText = lastText
        v.branch = branch
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
        var sawOutput: Set<String> = []
        var branch: String?
        for raw in lines.reversed() {
            guard let obj = json(raw), let type = obj["type"] as? String, let p = obj["payload"] as? [String: Any] else { continue }
            let when = date(obj["timestamp"]) ?? Date()
            let kind = p["type"] as? String ?? ""
            if type == "turn_context" || type == "session_meta", branch == nil,
               let git = p["git"] as? [String: Any], let b = git["branch"] as? String, !b.isEmpty { branch = b }
            if type == "event_msg" {
                switch kind {
                case "task_complete", "turn_complete":
                    if lastText == nil, let m = p["last_agent_message"] as? String { lastText = clean(m) }
                    if verdict == nil { verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file) }
                case "turn_aborted":
                    if verdict == nil { verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: "Turn interrupted", file: file) }
                case "error", "stream_error":
                    if verdict == nil {
                        let m = (p["message"] as? String) ?? "Error"
                        verdict = Verdict(phase: .turnDone, at: when, title: nil, lastText: nil, file: file, problem: classifyProblem(m))
                    }
                case "exec_approval_request", "apply_patch_approval_request", "request_user_input", "request_permissions", "elicitation_request":
                    if verdict == nil {
                        var what = kind == "apply_patch_approval_request" ? "Approve file changes" : "Approve a command"
                        if let c = p["command"] as? [String] { what = "Approve: " + describeTool("exec_command", input: ["command": c]).replacingOccurrences(of: "Running ", with: "") }
                        if kind == "request_user_input" || kind == "elicitation_request" { what = "Answer a question" }
                        verdict = Verdict(phase: .needsApproval(what), at: when, title: nil, lastText: nil, file: file, activity: what)
                    }
                case "task_started", "turn_started":
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file, activity: "Thinking") }
                case "user_message":
                    if let m = p["message"] as? String, title == nil { title = String(clean(m).prefix(80)) }
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file, activity: "Thinking") }
                case "agent_message":
                    if lastText == nil, let m = p["message"] as? String { lastText = clean(m) }
                default: break
                }
            } else if type == "response_item" {
                switch kind {
                case "function_call_output", "custom_tool_call_output":
                    if let id = p["call_id"] as? String { sawOutput.insert(id) }
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file, activity: "Thinking") }
                case "function_call", "custom_tool_call", "local_shell_call":
                    if verdict == nil, let id = p["call_id"] as? String, !sawOutput.contains(id) {
                        let name = p["name"] as? String ?? (kind == "local_shell_call" ? "shell" : "tool")
                        var input: [String: Any] = [:]
                        if let a = p["arguments"] as? String, let d = a.data(using: .utf8),
                           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { input = o }
                        if let action = p["action"] as? [String: Any] { input = action }
                        verdict = Verdict(phase: .toolPending(name), at: when, title: nil, lastText: nil, file: file,
                                          activity: describeTool(name, input: input))
                    }
                case "message":
                    let role = p["role"] as? String ?? ""
                    let text = ((p["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
                    if role == "user", title == nil, !text.isEmpty, !text.hasPrefix("<") { title = String(clean(text).prefix(80)) }
                    if role == "assistant", lastText == nil, !text.isEmpty { lastText = clean(text) }
                    if verdict == nil { verdict = Verdict(phase: role == "assistant" ? .turnDone : .working, at: when, title: nil, lastText: nil, file: file) }
                case "reasoning":
                    if verdict == nil { verdict = Verdict(phase: .working, at: when, title: nil, lastText: nil, file: file, activity: "Thinking") }
                default: break
                }
            }
            if verdict != nil, title != nil, lastText != nil, branch != nil { break }
        }
        guard var v = verdict else { return nil }
        v.title = title
        v.lastText = lastText
        v.branch = branch
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
