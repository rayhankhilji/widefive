import Foundation
import Security

/// Claude Code cloud sessions (claude.ai/code, `claude --cloud`, the Claude app's Cloud sessions), opt-in.
/// When switched on in the menu, widefive reads the sign-in Claude Code already keeps in your Keychain
/// ("Claude Code-credentials" — macOS asks once) and asks the same endpoint `claude --teleport` uses for your sessions
/// and their live state. Read-only: nothing is written back, tokens are never refreshed or stored by widefive.
public final class CloudSessions {
    public static let shared = CloudSessions()

    public enum Status: Error, Equatable {
        case off
        case ok(Int)
        /// No Claude Code sign-in on this Mac (or it's an API-key login).
        case noSignIn
        /// The sign-in expired; Claude Code refreshes it the next time it runs.
        case expired
        /// macOS refused (you clicked Deny on the Keychain prompt).
        case keychainDenied
        case error(String)
    }

    /// One cloud session, already mapped to the bar's states.
    public struct Session: Equatable {
        public var id: String
        public var title: String
        public var repo: String?
        public var branch: String?
        public var state: Agent.State
        public var message: String?
        public var updated: Date
    }

    private let queue = DispatchQueue(label: "widefive.cloud-sessions", qos: .utility)
    private let lock = NSLock()
    private var _sessions: [Session] = []
    private var _status: Status = .off
    private var lastFetch: Date = .distantPast
    private var inFlight = false
    private var token: (value: String, expires: Date?)?
    public var enabled = false {
        didSet {
            if !enabled { lock.lock(); _sessions = []; _status = .off; token = nil; lock.unlock() }
            else if !oldValue { lastFetch = .distantPast }
        }
    }

    public var sessions: [Session] { lock.lock(); defer { lock.unlock() }; return _sessions }
    public var status: Status { lock.lock(); defer { lock.unlock() }; return _status }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/code/sessions")!
    static let interval: TimeInterval = 8

    /// Called from each agent scan; fetches in the background at most every `interval` seconds.
    public func refreshIfNeeded() {
        guard enabled else { return }
        lock.lock()
        guard !inFlight, Date().timeIntervalSince(lastFetch) >= Self.interval else { lock.unlock(); return }
        inFlight = true
        lastFetch = Date()
        lock.unlock()
        queue.async { [weak self] in self?.fetch() }
    }

    private func finish(_ status: Status, _ sessions: [Session]? = nil) {
        lock.lock()
        _status = status
        if let sessions { _sessions = sessions } else if case .ok = status {} else { _sessions = [] }
        inFlight = false
        lock.unlock()
    }

    // MARK: Token

    /// Reads Claude Code's own OAuth sign-in. The first read shows macOS's Keychain prompt.
    static func readToken() -> Result<(String, Date?), Status> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecAttrAccount as String] = NSUserName()
        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            query.removeValue(forKey: kSecAttrAccount as String)
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }
        var data = item as? Data
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { return .failure(.keychainDenied) }
        if data == nil {
            // Fallback some setups use instead of the Keychain.
            data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/.credentials.json")
        }
        guard let data else { return .failure(.noSignIn) }
        return parseToken(data)
    }

    static func parseToken(_ data: Data) -> Result<(String, Date?), Status> {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = o["claudeAiOauth"] as? [String: Any], let t = oauth["accessToken"] as? String, !t.isEmpty else {
            return .failure(.noSignIn)
        }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) }
        return .success((t, exp))
    }

    // MARK: Fetch

    private func fetch() {
        if token == nil || (token?.expires.map { $0 < Date().addingTimeInterval(30) } ?? false) {
            switch Self.readToken() {
            case .success(let t):
                token = t
                if let exp = t.1, exp < Date() { token = nil; finish(.expired); return }
            case .failure(let s):
                token = nil; finish(s); return
            }
        }
        guard let t = token else { finish(.noSignIn); return }
        var req = URLRequest(url: Self.endpoint, timeoutInterval: 8)
        req.setValue("Bearer \(t.value)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("widefive/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var result: (Data?, Int)?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            result = (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        guard let (data, code) = result else { finish(.error("no response")); return }
        switch code {
        case 200:
            let list = Self.parseSessions(data ?? Data())
            finish(.ok(list.count), list)
        case 401:
            // Re-read once: Claude Code may have refreshed it since.
            token = nil
            finish(.expired)
        case 403:
            finish(.error("cloud sessions aren't enabled for this account"))
        default:
            finish(.error("HTTP \(code)"))
        }
    }

    // MARK: Mapping

    /// The list endpoint's sessions, mapped the way Claude Code's own session list maps them:
    /// requires_action → needs you · idle + completed → done · failed → error · running → working.
    static func parseSessions(_ data: Data, now: Date = Date()) -> [Session] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = o["data"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? { (v as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) } }
        var out: [Session] = []
        for s in list {
            guard let id = s["id"] as? String else { continue }
            let status = s["status"] as? String ?? ""
            if status == "archived" { continue }
            let worker = s["worker_status"] as? String
            let bucket = s["status_bucket"] as? String
            let meta = s["external_metadata"] as? [String: Any] ?? [:]
            let updated = date(s["last_event_at"]) ?? date(s["updated_at"]) ?? date(s["created_at"]) ?? now
            var state: Agent.State
            var message: String?
            if worker == "requires_action" {
                state = .waiting
                message = pendingAction(meta["pending_action"]) ?? "Needs your input"
            } else if worker == "idle" || status == "paused" {
                switch bucket {
                case "blocked": state = .waiting; message = "Needs your input"
                case "failed":
                    state = .failed
                    let detail = (meta["post_turn_summary"] as? [String: Any])?["status_detail"] as? String
                    message = detail.flatMap { $0.isEmpty ? nil : String($0.prefix(100)) } ?? "The last turn failed"
                case "working": state = .working
                default: state = .done; message = "Done — your turn"
                }
                if let summary = (meta["post_turn_summary"] as? [String: Any])?["summary"] as? String, state == .done, !summary.isEmpty {
                    message = String(summary.prefix(100))
                }
            } else if worker == "running", s["connection_status"] as? String == "disconnected" {
                state = .failed; message = "Lost contact with the cloud environment"
            } else {
                state = .working
            }
            // Keep the bar about what's live: anything working or waiting, and what finished in the last 3 hours.
            if state != .working && state != .waiting && now.timeIntervalSince(updated) > 3 * 3600 { continue }
            var repo: String?
            var branch: String?
            if let sources = (s["config"] as? [String: Any])?["sources"] as? [[String: Any]],
               let git = sources.first(where: { $0["type"] as? String == "git_repository" }) {
                if let url = git["url"] as? String { repo = url.split(separator: "/").last.map { String($0).replacingOccurrences(of: ".git", with: "") } }
                if repo == nil, let r = git["repo"] as? [String: Any] { repo = r["name"] as? String }
                branch = git["branch"] as? String ?? git["revision"] as? String
            }
            let title = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
            out.append(Session(id: id, title: title, repo: repo, branch: branch, state: state, message: message, updated: updated))
        }
        return out.sorted { $0.updated > $1.updated }
    }

    static func pendingAction(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        guard let d = v as? [String: Any] else { return nil }
        for k in ["description", "summary", "message", "title"] { if let s = d[k] as? String, !s.isEmpty { return String(s.prefix(100)) } }
        if let tool = d["tool_name"] as? String { return "Approve: \(tool)" }
        if let t = d["type"] as? String { return t.replacingOccurrences(of: "_", with: " ").capitalized }
        return nil
    }
}
