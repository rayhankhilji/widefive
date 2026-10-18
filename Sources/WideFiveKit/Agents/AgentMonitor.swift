import AppKit

/// Finds every coding agent on the Mac (terminal CLIs, desktop apps, web agents in browser tabs), works out whether
/// each one is busy or waiting for you, and brings the right window/tab to the front when asked.
///
/// Signals, strongest first — none of them needs any setup:
///  • hook       — optional: Claude Code / Codex / Cursor hooks installed from the menu (see AgentHooks)
///  • transcript — Claude Code and Codex journal every turn to disk; the last line says exactly what they're doing
///  • banner     — a macOS notification banner from the agent (Chrome/Safari for web agents, Cursor, Claude, ChatGPT,
///                 Terminal/iTerm2 bells) read through Accessibility
///  • badge      — a desktop app's Dock badge
///  • cpu        — a terminal agent whose process tree has burned no CPU for `idleSeconds` is sitting at a prompt
///  • title      — a browser tab whose title matches the attention patterns ("(1) …", "needs your approval")
public final class AgentMonitor {
    public static let shared = AgentMonitor()

    public private(set) var agents: [Agent] = []
    public var config = AgentsConfig()
    /// Main thread; fires whenever the list or any state changes.
    public var onChange: (() -> Void)?
    /// Main thread; an agent just started waiting for you.
    public var onAttention: ((Agent) -> Void)?
    public private(set) var lastScan: Date?
    /// Set for headless snapshots: the scan is skipped and this list is shown.
    public var demoAgents: [Agent]?

    public var waiting: [Agent] { agents.filter { $0.needsYou } }

    /// What's stopping detection from being complete, with the Settings pane that fixes it.
    public struct Hint: Equatable { public var text: String; public var settingsURL: String }
    public var hint: Hint? {
        if !AXIsProcessTrusted() {
            return Hint(text: "Allow Accessibility so widefive can see agent notifications and raise their windows",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        if let denied = AppScripting.automationDenied.first {
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: denied).first?.localizedName ?? denied
            return Hint(text: "Allow widefive to control \(name) to find agent tabs",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
        return nil
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "widefive.agents", qos: .utility)
    private var scanning = false
    private var scanCount = 0

    // Background-queue state.
    private struct CPUSample { var cpu: Double; var at: Double; var lastActive: Double; var busyRuns: Int }
    private var cpuSamples: [pid_t: CPUSample] = [:]
    /// Browser tabs are read on their own queue: a slow browser can delay tab rows, never the rest of the bar.
    private let tabsQueue = DispatchQueue(label: "widefive.agents.tabs", qos: .utility)
    private let focusQueue = DispatchQueue(label: "widefive.agents.focus", qos: .userInitiated)
    private let tabsLock = NSLock()
    private var tabsInFlight = false
    private var _cachedTabs: [AppScripting.Tab] = []
    private var cachedTabs: [AppScripting.Tab] {
        get { tabsLock.lock(); defer { tabsLock.unlock() }; return _cachedTabs }
        set { tabsLock.lock(); _cachedTabs = newValue; tabsLock.unlock() }
    }
    private var lastTabScan: Double = 0
    private var cachedBadges: [String: String] = [:]
    private var lastBadgeScan: Double = 0
    /// argv never changes for a process's lifetime, so it's read once per (pid, start time).
    private var argvCache: [pid_t: (start: Double, args: [String])] = [:]
    private var transcriptFiles: [pid_t: URL] = [:]
    private var transcriptCache: [URL: (stamp: String, verdict: AgentTranscripts.Verdict?)] = [:]
    private var codexCwdCache: [URL: String] = [:]
    private var bannersSeen: [String: Double] = [:]
    /// Banner-driven marks per agent id: the banner text, when it arrived and what it means.
    private var bannerMarks: [String: (text: String, at: Double, state: Agent.State)] = [:]
    /// Agents known only from a banner (cloud sessions, web agents whose tab we can't read).
    private var bannerAgents: [String: (agent: Agent, at: Double)] = [:]

    // Main-thread state.
    private var previousStates: [String: (state: Agent.State, since: Date)] = [:]
    /// Agents you've tapped: id → fingerprint of what was acknowledged. Same fingerprint → stays quiet.
    private var acknowledged: [String: String] = [:]

    static let busyCPUFraction = 0.015
    static let tabInterval = 3.0
    static let badgeInterval = 2.0

    public init() {}

    public func start() {
        guard timer == nil else { return }
        scan()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public func scan() {
        guard config.enabled else {
            if !agents.isEmpty { agents = []; onChange?() }
            return
        }
        if let demo = demoAgents { agents = demo; onChange?(); return }
        guard !scanning else { return }
        scanning = true
        let cfg = config
        let first = scanCount == 0
        scanCount += 1
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.collect(cfg)
            DispatchQueue.main.async {
                self.scanning = false
                self.publish(found, first: first)
            }
        }
    }

    /// One synchronous scan (tests, `widefive --agents`). Does not publish or fire callbacks.
    public func scanNow() -> [Agent] {
        let cfg = config
        return queue.sync { collect(cfg) }
    }

    /// Human-readable dump of what a scan sees, for `widefive --agents` and bug reports.
    public func diagnostics() -> String {
        var lines: [String] = []
        diagnostics { lines.append($0) }
        return lines.joined(separator: "\n")
    }

    /// Same, streamed line by line (so a slow step never hides what came before it).
    public func diagnostics(_ emit: @escaping (String) -> Void) {
        struct Out { let emit: (String) -> Void; func append(_ s: String) { emit(s) } }
        let out = Out(emit: emit)
        let procs = ProcessScanner.list()
        out.append("widefive agents diagnostics — \(Date())")
        out.append("accessibility: \(AXIsProcessTrusted() ? "granted" : "NOT granted (banners, badges and window raising need it)")")
        out.append("processes: \(procs.count) owned by uid \(getuid())")
        var matched = 0
        for p in procs {
            let args = ProcessScanner.arguments(p.pid)
            if let spec = AgentCatalog.terminalSpec(arguments: args, comm: p.comm, extra: config.processes) {
                matched += 1
                let cwd = ProcessScanner.cwd(p.pid) ?? "?"
                let host = ProcessScanner.hostApp(of: p.pid, in: Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a }))
                out.append("  pid \(p.pid) \(spec.name) comm=\(p.comm) tty=\(p.tty ?? "-") cwd=\(cwd) host=\(host?.localizedName ?? "-") argv=\(args.prefix(3).joined(separator: " "))")
                if spec.key == "claude" {
                    let files = AgentTranscripts.claudeTranscripts(cwd: cwd, since: Date(timeIntervalSince1970: p.startTime - 5))
                    out.append("    journals: \(files.map { $0.lastPathComponent })")
                    if let f = files.first, let v = AgentTranscripts.claudeVerdict(file: f) { out.append("    last entry: \(v.phase) at \(v.at) title=\(v.title ?? "-")") }
                } else if spec.key == "codex" {
                    let files = AgentTranscripts.codexTranscripts(since: Date(timeIntervalSince1970: p.startTime - 5)).filter { AgentTranscripts.codexCwd(file: $0) == cwd }
                    out.append("    rollouts: \(files.map { $0.lastPathComponent })")
                    if let f = files.first, let v = AgentTranscripts.codexVerdict(file: f) { out.append("    last entry: \(v.phase) at \(v.at) title=\(v.title ?? "-")") }
                }
            }
        }
        out.append("terminal agents matched: \(matched)")
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let agentApps = apps.compactMap { a in AgentCatalog.appSpec(bundleId: a.bundleIdentifier, name: a.localizedName, extra: config.apps).map { "\($0.name) (\(a.bundleIdentifier ?? "?"))" } }
        out.append("agent apps running: \(agentApps)")
        out.append("dock badges: \(AppScripting.dockBadges())")
        // macOS can make even the no-prompt permission check wait while a consent prompt is on screen; never hang on it.
        for b in AgentCatalog.browsers where AppScripting.isRunning(b.bundleId) {
            let p = Self.within(3) { AppScripting.permission(b.bundleId) }
            out.append("browser \(b.bundleId): automation \(p.map { "\($0)" } ?? "check timed out (a consent prompt is probably waiting on screen)")")
        }
        let tabs = config.scanBrowsers ? (Self.within(12) { AppScripting.browserTabs() } ?? []) : []
        cachedTabs = tabs
        out.append("browser tabs: \(tabs.count)")
        for t in tabs where AgentCatalog.siteSpec(url: t.url, extra: config.sites) != nil { out.append("  \(t.bundleId) w\(t.window) t\(t.index) \(t.url) — \(t.title)") }
        out.append("banners on screen: \(NotificationBanners.current())")
        out.append("hook events: \(AgentHooks.events().count)")
        out.append("claude code sessions (\(ClaudeSessions.directory.path)):")
        for e in ClaudeSessions.entries() {
            let (st, msg) = ClaudeSessions.state(of: e)
            out.append("  pid \(e.pid) \(e.kind ?? "?")/\(e.entrypoint ?? "?") status=\(e.status)\(e.waitingFor.map { " waitingFor=\($0)" } ?? "") → \(st)\(msg.map { " (\($0))" } ?? "") cwd=\(e.cwd ?? "?") name=\(e.name ?? "-")")
        }
        let errors = AppScripting.lastErrors
        if !errors.isEmpty { out.append("apple events errors: \(errors.map { "\($0.key): \($0.value.code) \($0.value.message)" })") }
        out.append("")
        lastTabScan = CACurrentMediaTime()
        for a in scanNow() { out.append("→ \(a.kind) \(a.name) [\(a.state)] via \(a.signal): \(a.detail)\(a.message.map { " — " + $0 } ?? "")") }
        if let h = hint { out.append("hint: \(h.text)") }
    }

    // MARK: Collecting (background queue)

    private func collect(_ cfg: AgentsConfig) -> [Agent] {
        let now = CACurrentMediaTime()
        let wall = Date()
        var out: [Agent] = []
        /// Agents whose state came from something stronger than a banner this scan (so a stale banner can't flip them).
        var strong: Set<String> = []
        /// Host app display names per agent id, for matching banners to agents.
        var hostNames: [String: String] = [:]
        let procs = ProcessScanner.list()
        var table: [pid_t: ProcessInfoRecord] = [:]
        var children: [pid_t: [pid_t]] = [:]
        for p in procs { table[p.pid] = p; children[p.ppid, default: []].append(p.pid) }
        let events = AgentHooks.events()
        let hooksByPid = Dictionary(events.map { ($0.pid, $0) }, uniquingKeysWith: { a, b in a.time > b.time ? a : b })

        // Terminal agents: pass 1 — who looks like one. The kernel's short name can't be trusted (the native Claude
        // installer runs a file called "2.0.14" through a `claude` symlink), so argv decides, cached per process.
        var matched: [pid_t: AgentCatalog.Spec] = [:]
        argvCache = argvCache.filter { entry in table[entry.key]?.startTime == entry.value.start }
        for p in procs where p.pid != 1 {
            let args: [String]
            if let c = argvCache[p.pid], c.start == p.startTime { args = c.args } else {
                args = ProcessScanner.arguments(p.pid)
                argvCache[p.pid] = (p.startTime, args)
            }
            if let spec = AgentCatalog.terminalSpec(arguments: args, comm: p.comm, extra: cfg.processes) { matched[p.pid] = spec }
        }
        // Pass 2 — drop wrappers (node shim → native binary, uv → python): keep the deepest process of a chain.
        var wrappers: Set<pid_t> = []
        for pid in matched.keys {
            var p = table[pid]?.ppid ?? 0
            for _ in 0..<4 {
                guard p > 1 else { break }
                if matched[p] != nil, table[p]?.tty == table[pid]?.tty { wrappers.insert(p) }
                p = table[p]?.ppid ?? 0
            }
        }
        // Claude Code's own status files: exact state for every session, and they name the real session process.
        let sessions = ClaudeSessions.entries()
        var sessionByPid: [pid_t: ClaudeSessions.Entry] = [:]
        for e in sessions where table[e.pid] != nil {
            sessionByPid[e.pid] = e
            if matched[e.pid] == nil { matched[e.pid] = AgentCatalog.terminal[0] }
            // A matched wrapper above or below the session process is the same session.
            var p = table[e.pid]?.ppid ?? 0
            for _ in 0..<4 { guard p > 1 else { break }; if matched[p] != nil { wrappers.insert(p) }; p = table[p]?.ppid ?? 0 }
            for k in children[e.pid] ?? [] where matched[k] != nil { wrappers.insert(k) }
            wrappers.remove(e.pid)
        }
        let live = matched.keys.filter { !wrappers.contains($0) }.sorted { (table[$0]?.startTime ?? 0) < (table[$1]?.startTime ?? 0) }
        transcriptFiles = transcriptFiles.filter { live.contains($0.key) }

        var hostedBy: Set<String> = []
        /// claude.ai/code session ids already shown through a local session (Remote Control), so their tab isn't doubled.
        var bridged: Set<String> = []
        for pid in live {
            guard let p = table[pid], let spec = matched[pid] else { continue }
            let cpu = subtreeCPU(pid, children: children)
            var sample = cpuSamples[pid] ?? CPUSample(cpu: cpu, at: now, lastActive: now, busyRuns: 0)
            let dt = max(0.001, now - sample.at)
            let busy = (cpu - sample.cpu) / dt > Self.busyCPUFraction
            if busy { sample.lastActive = now; sample.busyRuns += 1 } else { sample.busyRuns = 0 }
            sample.cpu = cpu; sample.at = now
            cpuSamples[pid] = sample
            let quiet = now - sample.lastActive
            let resumed = sample.busyRuns >= 2
            let started = Date(timeIntervalSince1970: p.startTime)
            let hook = hooksByPid[pid]
            let cwd = hook?.cwd ?? ProcessScanner.cwd(pid)
            let verdict = transcriptVerdict(pid: pid, key: spec.key, cwd: cwd, started: started)

            var state: Agent.State = quiet >= cfg.idleSeconds ? .waiting : .working
            var signal = "cpu"
            var message: String?
            var since = wall
            let id = "proc:\(pid)"
            let session = sessionByPid[pid]
            if let session {
                signal = "session"
                (state, message) = ClaudeSessions.state(of: session)
                since = session.statusUpdatedAt ?? wall
                if state == .done, let last = verdict?.lastText, verdict?.phase == .turnDone { message = last }
                strong.insert(id)
            } else if let hook, hook.time.timeIntervalSince1970 >= p.startTime - 1 {
                signal = "hook"
                state = hook.state
                message = hook.message
                since = hook.time
                if state == .waiting, resumed { state = .working; message = nil }
                strong.insert(id)
            } else if let v = verdict {
                signal = "transcript"
                since = v.at
                switch v.phase {
                case .working:
                    state = .working
                case .turnDone:
                    if resumed, quiet < 1 { state = .working } else { state = .done; message = v.lastText ?? "Done — your turn" }
                case .toolPending(let tool):
                    let toolRunning = busy || (children[pid] ?? []).contains { (table[$0]?.startTime ?? 0) >= v.at.timeIntervalSince1970 - 1 }
                    if toolRunning || quiet < 2 { state = .working; message = "Running \(tool)" }
                    else { state = .waiting; message = "Waiting for your permission: \(tool)" }
                case .needsApproval(let what):
                    state = .waiting; message = "Needs your approval (\(what))"
                }
                strong.insert(id)
            }
            // Without an exact signal, a process that has done nothing for a long while is waiting on something.
            if session == nil, state == .working, quiet >= max(cfg.idleSeconds * 5, 30) { state = .waiting; signal = "cpu"; message = message ?? "No activity for a while" }

            let project = cwd.map { ($0 as NSString).lastPathComponent }
            let host = ProcessScanner.hostApp(of: pid, in: table)
            let hostId = host?.bundleIdentifier
            if let hostId { hostedBy.insert(hostId) }
            if let b = session?.bridgeSessionId { bridged.insert(b) }
            if let sid = session?.sessionId { bridged.insert(sid) }
            let tty = hook?.tty ?? p.tty
            var detail = project ?? (tty ?? "")
            let title = (session?.nameIsUser == true ? session?.name : nil) ?? verdict?.title
            if let t = title, !t.isEmpty { detail = detail.isEmpty ? t : "\(detail) — \(t.prefix(48))" }
            if let host, let hn = host.localizedName { hostNames[id] = hn; if title == nil { detail = detail.isEmpty ? hn : "\(detail) · \(hn)" } }
            var kind: Agent.Kind = .terminal
            var focus: Agent.Focus = .terminal(bundleId: hostId, tty: tty, window: project)
            if let hostId, AgentCatalog.terminalHosts[hostId] == nil {
                // Running inside an app (Claude desktop's Code tab, VS Code, Cursor…): bring that app's window up.
                kind = .app
                focus = .app(bundleId: hostId, window: project)
            } else if hostId == nil, tty == nil, let s = session, s.kind == "bg" || s.kind == "daemon-worker" {
                // A background session has no window: open one attached to it.
                focus = .command("claude attach \(s.sessionId ?? String(pid))", cwd: cwd)
            }
            out.append(Agent(id: id, kind: kind, name: spec.name, detail: detail, state: state, since: since, message: message,
                             color: spec.color, logo: spec.logo, icon: spec.icon, hostBundleId: hostId,
                             focus: focus, signal: signal))
        }

        // Dock badges (needs Accessibility; cached briefly because the AX walk isn't free).
        if now - lastBadgeScan >= Self.badgeInterval { cachedBadges = AppScripting.dockBadges(); lastBadgeScan = now }
        let badges = cachedBadges

        // Desktop apps.
        let cursorHooks = events.filter { $0.kind == "cursor" }.sorted { $0.time > $1.time }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier,
                  let spec = AgentCatalog.appSpec(bundleId: bid, name: app.localizedName, extra: cfg.apps) else { continue }
            let badge = badges[app.localizedName ?? ""] ?? badges[spec.name]
            let hosting = hostedBy.contains(bid)
            var state: Agent.State = .idle
            var signal = "none"
            var message: String?
            var window: String?
            let id = "app:\(bid)"
            if let badge {
                state = .waiting; signal = "badge"; message = badge == "•" ? "Has something for you" : "\(badge) waiting"
            }
            if bid.contains("todesktop"), let h = cursorHooks.first {
                // Cursor's own agent reports through hooks; the newest event wins.
                signal = "hook"; state = h.state; message = h.message ?? message
                window = h.cwd.map { ($0 as NSString).lastPathComponent }
                strong.insert(id)
            }
            guard spec.standalone || badge != nil || signal == "hook" else { continue }
            if hosting, signal == "none" { continue } // the terminal agent row already covers it
            hostNames[id] = app.localizedName ?? spec.name
            out.append(Agent(id: id, kind: .app, name: spec.name, detail: window ?? (app.localizedName ?? spec.name), state: state, since: wall,
                             message: message, color: spec.color, logo: spec.logo ?? "app:\(bid)", icon: spec.icon, hostBundleId: bid,
                             focus: .app(bundleId: bid, window: window), signal: signal))
        }

        // Browser tabs.
        if cfg.scanBrowsers {
            if now - lastTabScan >= Self.tabInterval { lastTabScan = now; refreshTabs() }
            let patterns = cfg.attentionTitles.isEmpty ? AgentCatalog.defaultAttentionTitles : cfg.attentionTitles
            var seenURLs: Set<String> = []
            var browserNames: [String: String] = [:]
            for t in cachedTabs {
                guard let spec = AgentCatalog.siteSpec(url: t.url, extra: cfg.sites) else { continue }
                if bridged.contains(where: { t.url.contains($0) }) { continue }
                let key = "\(t.bundleId)|\(t.url)"
                guard !seenURLs.contains(key) else { continue }
                seenURLs.insert(key)
                let needs = AgentCatalog.titleNeedsYou(t.title, patterns: patterns)
                let title = t.title.isEmpty ? (AgentCatalog.domain(t.url) ?? t.url) : t.title
                let id = "tab:\(key)"
                if browserNames[t.bundleId] == nil {
                    browserNames[t.bundleId] = NSRunningApplication.runningApplications(withBundleIdentifier: t.bundleId).first?.localizedName ?? t.bundleId
                }
                hostNames[id] = browserNames[t.bundleId] ?? ""
                out.append(Agent(id: id, kind: .web, name: spec.name, detail: title, state: needs ? .waiting : .idle, since: wall,
                                 message: needs ? "Tab says: \(title)" : nil, color: spec.color, logo: spec.logo, icon: spec.icon,
                                 hostBundleId: t.bundleId, focus: .tab(bundleId: t.bundleId, url: t.url, title: t.title), signal: needs ? "title" : "none"))
            }
        }

        applyBanners(to: &out, strong: strong, hostNames: hostNames, now: now)

        // Forget state of processes that are gone.
        let alive = Set(procs.map { $0.pid })
        cpuSamples = cpuSamples.filter { alive.contains($0.key) }
        return out
    }

    /// Runs `work` on a background thread and gives up waiting after `seconds` (the work itself carries on).
    static func within<T>(_ seconds: Double, _ work: @escaping () -> T) -> T? {
        let sem = DispatchSemaphore(value: 0)
        let box = NSLock()
        var result: T?
        DispatchQueue.global(qos: .userInitiated).async {
            let r = work()
            box.lock(); result = r; box.unlock()
            sem.signal()
        }
        guard sem.wait(timeout: .now() + seconds) == .success else { return nil }
        box.lock(); defer { box.unlock() }
        return result
    }

    private func refreshTabs() {
        tabsLock.lock()
        if tabsInFlight { tabsLock.unlock(); return }
        tabsInFlight = true
        tabsLock.unlock()
        tabsQueue.async { [weak self] in
            let tabs = AppScripting.browserTabs()
            guard let self else { return }
            self.tabsLock.lock()
            self._cachedTabs = tabs
            self.tabsInFlight = false
            self.tabsLock.unlock()
        }
    }

    /// Reads tabs synchronously (diagnostics only).
    func refreshTabsNow() { cachedTabs = AppScripting.browserTabs() }

    /// CPU seconds of a process plus its descendants (tools it is running), three levels deep.
    private func subtreeCPU(_ pid: pid_t, children: [pid_t: [pid_t]], depth: Int = 0) -> Double {
        var total = ProcessScanner.cpuTime(pid) ?? 0
        guard depth < 3, let kids = children[pid] else { return total }
        for k in kids { total += subtreeCPU(k, children: children, depth: depth + 1) }
        return total
    }

    // MARK: Transcripts

    /// The journal entry for a Claude Code / Codex process, re-parsed only when its file changes.
    private func transcriptVerdict(pid: pid_t, key: String, cwd: String?, started: Date) -> AgentTranscripts.Verdict? {
        guard key == "claude" || key == "codex", let cwd else { return nil }
        let since = started.addingTimeInterval(-5)
        var file = transcriptFiles[pid]
        if let f = file, !FileManager.default.fileExists(atPath: f.path) { file = nil; transcriptFiles[pid] = nil }
        if file == nil {
            let taken = Set(transcriptFiles.filter { $0.key != pid }.values)
            let candidates: [URL]
            if key == "claude" {
                candidates = AgentTranscripts.claudeTranscripts(cwd: cwd, since: since)
            } else {
                candidates = AgentTranscripts.codexTranscripts(since: since).filter { f in
                    let c = codexCwdCache[f] ?? AgentTranscripts.codexCwd(file: f) ?? ""
                    codexCwdCache[f] = c
                    return c == cwd
                }
            }
            file = candidates.first { !taken.contains($0) }
            if let f = file { transcriptFiles[pid] = f }
        }
        guard let f = file else { return nil }
        // Re-parse only when the file changed. stat(2), not URL resource values: those are cached per URL object.
        var st = stat()
        let stamp = stat(f.path, &st) == 0 ? "\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)|\(st.st_size)" : UUID().uuidString
        if let c = transcriptCache[f], c.stamp == stamp { return c.verdict }
        let v = key == "claude" ? AgentTranscripts.claudeVerdict(file: f) : AgentTranscripts.codexVerdict(file: f)
        transcriptCache[f] = (stamp, v)
        if transcriptCache.count > 64 { transcriptCache = transcriptCache.filter { transcriptFiles.values.contains($0.key) } }
        return v
    }

    // MARK: Banners

    /// Reads the banners on screen, remembers the new ones, matches each to the agent it is about and marks it.
    /// A banner from an agent we can't see otherwise (a cloud session, a web agent in a tab we couldn't read) becomes
    /// its own entry, so "Claude Code finished" from the Claude app or claude.ai still lands on the bar.
    private func applyBanners(to out: inout [Agent], strong: Set<String>, hostNames: [String: String], now: Double) {
        let banners = NotificationBanners.current()
        var fresh: [NotificationBanners.Banner] = []
        for b in banners where bannersSeen[b.id] == nil { bannersSeen[b.id] = now; fresh.append(b) }
        bannersSeen = bannersSeen.filter { now - $0.value < 3600 }
        for b in fresh {
            let state = Self.bannerState(b.text)
            if let i = Self.match(banner: b, agents: out, hostNames: hostNames) {
                bannerMarks[out[i].id] = (b.text, now, state)
            } else if let a = Self.agentFromBanner(b, state: state, tabs: cachedTabs) {
                bannerAgents[a.id] = (a, now)
            }
        }
        let ids = Set(out.map { $0.id })
        bannerMarks = bannerMarks.filter { ids.contains($0.key) && now - $0.value.at < 6 * 3600 }
        bannerAgents = bannerAgents.filter { now - $0.value.at < 3 * 3600 }
        for i in out.indices {
            guard let mark = bannerMarks[out[i].id] else { continue }
            // A stronger signal that changed after the banner wins; otherwise the banner decides.
            if strong.contains(out[i].id), out[i].since.timeIntervalSince1970 > Date().timeIntervalSince1970 - (now - mark.at) {
                bannerMarks[out[i].id] = nil
                continue
            }
            if !strong.contains(out[i].id) || out[i].state != .waiting {
                out[i].state = mark.state
                out[i].signal = "banner"
                out[i].message = mark.text
                out[i].since = Date().addingTimeInterval(mark.at - now)
            }
        }
        for (_, entry) in bannerAgents where !out.contains(where: { $0.id == entry.agent.id }) { out.append(entry.agent) }
    }

    /// "Needs your approval", "has a question", "waiting for input" → waiting; anything else from an agent → done.
    static func bannerState(_ text: String) -> Agent.State {
        let t = text.lowercased()
        let asks = ["needs your", "need your", "needs input", "waiting for your", "waiting for input", "waiting on you", "permission",
                    "approve", "approval", "allow ", "question", "asks", "asking", "respond", "reply needed", "action required", "confirm"]
        return asks.contains { t.contains($0) } ? .waiting : .done
    }

    /// An entry for a banner about an agent that has no row yet: which agent (by app or site), and how to get to it.
    static func agentFromBanner(_ b: NotificationBanners.Banner, state: Agent.State, tabs: [AppScripting.Tab]) -> Agent? {
        let text = b.text
        let lower = text.lowercased()
        let appName = b.app ?? ""
        let bundle = b.bundleId ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == appName }?.bundleIdentifier
        var spec: AgentCatalog.Spec?
        var focus: Agent.Focus?
        var kind: Agent.Kind = .web
        if let app = AgentCatalog.appSpec(bundleId: bundle, name: appName), app.standalone {
            spec = AgentCatalog.Spec(key: app.name, name: app.name, color: app.color, logo: app.logo, icon: app.icon)
            if let bundle { focus = .app(bundleId: bundle, window: nil) }
            kind = .app
        } else {
            for (match, s) in AgentCatalog.sites {
                let host = String(match.split(separator: "/").first ?? "")
                let named = s.name.count >= 4 && lower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: s.name.lowercased()) + "\\b",
                                                              options: .regularExpression) != nil
                if lower.contains(host) || named {
                    spec = s
                    if let tab = tabs.first(where: { AgentCatalog.siteSpec(url: $0.url)?.key == s.key }) {
                        focus = .tab(bundleId: tab.bundleId, url: tab.url, title: tab.title)
                    } else {
                        focus = .url("https://" + match)
                    }
                    break
                }
            }
        }
        guard let spec, let focus else { return nil }
        let id = "banner:\(spec.key):\(abs(text.hashValue))"
        return Agent(id: id, kind: kind, name: spec.name, detail: String(text.prefix(80)), state: state, since: Date(),
                     message: text, color: spec.color, logo: spec.logo, icon: spec.icon, hostBundleId: bundle, focus: focus, signal: "banner")
    }

    /// Which agent a banner is about: the host app's name, the agent's name or site, and the project / tab words.
    static func match(banner b: NotificationBanners.Banner, agents: [Agent], hostNames: [String: String]) -> Int? {
        let text = b.text.lowercased()
        let app = (b.app ?? "").lowercased()
        var best: (Int, Int)?
        for (i, a) in agents.enumerated() {
            var score = 0
            let host = (hostNames[a.id] ?? "").lowercased()
            if !host.isEmpty, app == host || text.hasPrefix(host) { score += 2 }
            if let bid = b.bundleId, bid == a.hostBundleId { score += 3 }
            if text.contains(a.name.lowercased()) { score += 2 }
            if let dom = a.logo?.split(separator: "|").compactMap({ $0.hasPrefix("web:") ? String($0.dropFirst(4)) : nil }).first, text.contains(dom.lowercased()) { score += 2 }
            for word in a.detail.lowercased().split(whereSeparator: { " ·—-/".contains($0) }) where word.count >= 4 && text.contains(word) { score += 3; break }
            if a.kind == .web, ["google chrome", "chrome", "safari", "arc", "brave browser", "microsoft edge", "vivaldi", "dia", "comet"].contains(app) { score += 1 }
            if a.kind == .terminal, ["terminal", "iterm2", "iterm", "warp", "ghostty", "kitty", "alacritty", "wezterm"].contains(app) { score += 1 }
            if score > (best?.1 ?? 0) { best = (i, score) }
        }
        guard let best, best.1 >= 3 else { return nil }
        return best.0
    }

    // MARK: Publishing (main thread)

    /// What "seen" refers to: the same state with the same message stays quiet; any change alerts again.
    /// Exact signals carry the time the state changed, so a new turn finishing alerts again even with the same text.
    static func fingerprint(_ a: Agent) -> String {
        let stamp = ["session", "hook", "transcript"].contains(a.signal) ? Int(a.since.timeIntervalSince1970) : 0
        return "\(a.state.rawValue)|\(a.message ?? "")|\(stamp)"
    }

    private func publish(_ found: [Agent], first: Bool) {
        guard demoAgents == nil else { return }
        var next: [Agent] = []
        var attention: [Agent] = []
        var states: [String: (state: Agent.State, since: Date)] = [:]
        for var a in found {
            if a.needsYou, acknowledged[a.id] == Self.fingerprint(a) {
                a.state = .idle; a.signal = "seen"
            } else if !a.needsYou {
                acknowledged.removeValue(forKey: a.id)
            }
            if let prev = previousStates[a.id] {
                if prev.state == a.state { a.since = min(prev.since, a.since) } else if a.needsYou { attention.append(a) }
            } else if a.needsYou, !first || a.signal == "banner" {
                attention.append(a)
            }
            states[a.id] = (a.state, a.since)
            next.append(a)
        }
        next.sort { l, r in
            if l.needsYou != r.needsYou { return l.needsYou }
            if l.kind != r.kind { return rank(l.kind) < rank(r.kind) }
            return l.name < r.name
        }
        let ids = Set(next.map { $0.id })
        acknowledged = acknowledged.filter { ids.contains($0.key) }
        let changed = next != agents
        previousStates = states
        agents = next
        lastScan = Date()
        if changed { onChange?() }
        for a in attention { onAttention?(a) }
    }

    private func rank(_ k: Agent.Kind) -> Int { k == .terminal ? 0 : k == .app ? 1 : 2 }

    // MARK: Focusing

    /// Brings the agent's window/tab to the front. Runs off the main thread (AppleScript can take a moment).
    public func focus(_ agent: Agent, done: ((Bool) -> Void)? = nil) {
        acknowledge(agent.id)
        focusQueue.async {
            let ok: Bool
            switch agent.focus {
            case .app(let bid, let window):
                AppScripting.activate(bid)
                AppScripting.raiseWindow(bundleId: bid, titleContaining: window)
                ok = true
            case .terminal(let bid, let tty, let window):
                ok = AppScripting.focusTerminal(bundleId: bid, tty: tty, window: window)
            case .tab(let bid, let url, let title):
                ok = AppScripting.focusTab(bundleId: bid, url: url, title: title)
            case .command(let cmd, let cwd):
                ok = DispatchQueue.main.sync { AppScripting.openCommand(cmd, cwd: cwd) }
            case .url(let u):
                ok = DispatchQueue.main.sync { URL(string: u).map { NSWorkspace.shared.open($0) } ?? false }
            }
            DispatchQueue.main.async { done?(ok) }
        }
    }

    /// Marks an agent as seen (after you tap it) so the bar stops pulsing until something about it changes.
    public func acknowledge(_ id: String) {
        guard let i = agents.firstIndex(where: { $0.id == id }), agents[i].needsYou else { return }
        acknowledged[id] = Self.fingerprint(agents[i])
        agents[i].state = .idle
        agents[i].signal = "seen"
        previousStates[id] = (.idle, Date())
        queue.async { [weak self] in self?.bannerMarks[id] = nil; self?.bannerAgents[id] = nil }
        onChange?()
    }

    // MARK: Demo data (README media, --snapshot agents:demo)

    public static func demoList() -> [Agent] {
        let now = Date()
        return [
            Agent(id: "d1", kind: .terminal, name: "Claude Code", detail: "widefive — add the agent strip · Terminal", state: .waiting, since: now.addingTimeInterval(-40),
                  message: "Waiting for your permission: Bash", color: "#d97757", logo: "web:claude.ai", icon: "sparkle",
                  hostBundleId: "com.apple.Terminal", focus: .terminal(bundleId: "com.apple.Terminal", tty: "ttys003", window: "widefive"), signal: "transcript"),
            Agent(id: "d2", kind: .web, name: "Codex", detail: "Add agent monitor — Codex", state: .waiting, since: now.addingTimeInterval(-12),
                  message: "Google Chrome · chatgpt.com · Your task is ready for review", color: "#10a37f", logo: "web:chatgpt.com", icon: "terminal", hostBundleId: "com.google.Chrome",
                  focus: .tab(bundleId: "com.google.Chrome", url: "https://chatgpt.com/codex", title: ""), signal: "banner"),
            Agent(id: "d3", kind: .terminal, name: "Gemini CLI", detail: "api · iTerm2", state: .working, since: now.addingTimeInterval(-200),
                  message: nil, color: "#4285f4", logo: "web:gemini.google.com", icon: "diamond", hostBundleId: "com.googlecode.iterm2",
                  focus: .terminal(bundleId: "com.googlecode.iterm2", tty: "ttys005", window: nil), signal: "cpu"),
            Agent(id: "d4", kind: .app, name: "Cursor", detail: "landing-page", state: .working, since: now.addingTimeInterval(-90),
                  message: nil, color: "#8b5cf6", logo: "web:cursor.com", icon: "cursorarrow", hostBundleId: "com.todesktop.230313mzl4w4u92",
                  focus: .app(bundleId: "com.todesktop.230313mzl4w4u92", window: nil), signal: "hook"),
            Agent(id: "d5", kind: .web, name: "Claude Code", detail: "Claude Code", state: .idle, since: now.addingTimeInterval(-300),
                  message: nil, color: "#d97757", logo: "web:claude.ai", icon: "sparkle", hostBundleId: "com.google.Chrome",
                  focus: .tab(bundleId: "com.google.Chrome", url: "https://claude.ai/code", title: ""), signal: "none"),
            Agent(id: "d6", kind: .app, name: "ChatGPT", detail: "ChatGPT", state: .idle, since: now.addingTimeInterval(-900),
                  message: nil, color: "#10a37f", logo: "web:chatgpt.com", icon: "bubble.left.fill", hostBundleId: "com.openai.chat",
                  focus: .app(bundleId: "com.openai.chat", window: nil), signal: "none"),
        ]
    }
}
