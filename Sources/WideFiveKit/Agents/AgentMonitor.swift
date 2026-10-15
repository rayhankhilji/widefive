import AppKit

/// Finds every coding agent on the Mac (terminal CLIs, desktop apps, web agents in browser tabs), works out whether
/// each one is busy or waiting for you, and brings the right window/tab to the front when asked.
///
/// Signals, strongest first:
///  • hook  — Claude Code / Codex / Cursor tell us directly (see AgentHooks)
///  • badge — a desktop app's Dock badge (ChatGPT, Claude, Cursor… badge when a reply is ready)
///  • cpu   — a terminal agent whose process tree has burned no CPU for `idleSeconds` is sitting at a prompt
///  • title — a browser tab whose title matches the attention patterns ("(1) …", "needs your approval")
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

    private var timer: Timer?
    private let queue = DispatchQueue(label: "widefive.agents", qos: .utility)
    private var scanning = false
    private var scanCount = 0

    // Background-queue state.
    private struct CPUSample { var cpu: Double; var at: Double; var lastActive: Double; var busyRuns: Int }
    private var cpuSamples: [pid_t: CPUSample] = [:]
    private var cachedTabs: [AppScripting.Tab] = []
    private var lastTabScan: Double = 0
    private var cachedBadges: [String: String] = [:]
    private var lastBadgeScan: Double = 0

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

    // MARK: Collecting (background queue)

    private func collect(_ cfg: AgentsConfig) -> [Agent] {
        let now = CACurrentMediaTime()
        let wall = Date()
        var out: [Agent] = []
        let procs = ProcessScanner.list()
        var table: [pid_t: ProcessInfoRecord] = [:]
        var children: [pid_t: [pid_t]] = [:]
        for p in procs { table[p.pid] = p; children[p.ppid, default: []].append(p.pid) }
        let events = AgentHooks.events()
        let hooksByPid = Dictionary(events.map { ($0.pid, $0) }, uniquingKeysWith: { a, b in a.time > b.time ? a : b })

        // Terminal agents: pass 1 — who looks like one.
        var matched: [pid_t: AgentCatalog.Spec] = [:]
        for p in procs {
            let c = p.comm.lowercased()
            let candidate = AgentCatalog.terminal.contains { c.hasPrefix($0.key.prefix(15)) }
                || AgentCatalog.interpreters.contains(c)
                || cfg.processes.keys.contains { c.hasPrefix($0.lowercased().prefix(15)) }
            guard candidate else { continue }
            let args = ProcessScanner.arguments(p.pid)
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

        var hostedBy: Set<String> = []
        for (pid, spec) in matched where !wrappers.contains(pid) {
            guard let p = table[pid] else { continue }
            let cpu = subtreeCPU(pid, children: children)
            var sample = cpuSamples[pid] ?? CPUSample(cpu: cpu, at: now, lastActive: now, busyRuns: 0)
            let dt = max(0.001, now - sample.at)
            let busy = (cpu - sample.cpu) / dt > Self.busyCPUFraction
            if busy { sample.lastActive = now; sample.busyRuns += 1 } else { sample.busyRuns = 0 }
            sample.cpu = cpu; sample.at = now
            cpuSamples[pid] = sample
            let quiet = now - sample.lastActive
            var state: Agent.State = quiet >= cfg.idleSeconds ? .waiting : .working
            var signal = "cpu"
            var message: String?
            let hook = hooksByPid[pid]
            if let hook, hook.time.timeIntervalSince1970 >= p.startTime - 1 {
                signal = "hook"
                state = hook.state
                message = hook.message
                // The hook said "waiting" but the user has clearly resumed (sustained CPU): trust the CPU.
                if state == .waiting, sample.busyRuns >= 2 { state = .working; message = nil }
                // The hook said "working" but nothing has happened for a long while: it's waiting on something.
                if state == .working, quiet >= max(cfg.idleSeconds * 5, 30) { state = .waiting; signal = "cpu"; message = nil }
            }
            let cwd = hook?.cwd ?? ProcessScanner.cwd(pid)
            let project = cwd.map { ($0 as NSString).lastPathComponent }
            let host = ProcessScanner.hostApp(of: pid, in: table)
            let hostId = host?.bundleIdentifier
            if let hostId { hostedBy.insert(hostId) }
            let tty = hook?.tty ?? p.tty
            var detail = project ?? (tty ?? "")
            if let host, let hn = host.localizedName { detail = detail.isEmpty ? hn : "\(detail) · \(hn)" }
            out.append(Agent(id: "proc:\(pid)", kind: .terminal, name: spec.name, detail: detail, state: state, since: wall, message: message,
                             color: spec.color, logo: spec.logo, icon: spec.icon, hostBundleId: hostId,
                             focus: .terminal(bundleId: hostId, tty: tty, window: project), signal: signal))
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
            if let badge {
                state = .waiting; signal = "badge"; message = badge == "•" ? "Has something for you" : "\(badge) waiting"
            }
            if bid.contains("todesktop"), let h = cursorHooks.first {
                // Cursor's own agent reports through hooks; the newest event wins.
                signal = "hook"; state = h.state; message = h.message ?? message
                window = h.cwd.map { ($0 as NSString).lastPathComponent }
            }
            guard spec.standalone || badge != nil || signal == "hook" else { continue }
            if hosting, signal == "none" { continue } // the terminal agent row already covers it
            out.append(Agent(id: "app:\(bid)", kind: .app, name: spec.name, detail: window ?? (app.localizedName ?? spec.name), state: state, since: wall,
                             message: message, color: spec.color, logo: spec.logo ?? "app:\(bid)", icon: spec.icon, hostBundleId: bid,
                             focus: .app(bundleId: bid, window: window), signal: signal))
        }

        // Browser tabs.
        if cfg.scanBrowsers {
            if now - lastTabScan >= Self.tabInterval { cachedTabs = AppScripting.browserTabs(); lastTabScan = now }
            let patterns = cfg.attentionTitles.isEmpty ? AgentCatalog.defaultAttentionTitles : cfg.attentionTitles
            var seenURLs: Set<String> = []
            for t in cachedTabs {
                guard let spec = AgentCatalog.siteSpec(url: t.url, extra: cfg.sites) else { continue }
                let key = "\(t.bundleId)|\(t.url)"
                guard !seenURLs.contains(key) else { continue }
                seenURLs.insert(key)
                let needs = AgentCatalog.titleNeedsYou(t.title, patterns: patterns)
                let title = t.title.isEmpty ? (AgentCatalog.domain(t.url) ?? t.url) : t.title
                out.append(Agent(id: "tab:\(key)", kind: .web, name: spec.name, detail: title, state: needs ? .waiting : .idle, since: wall,
                                 message: needs ? "Tab says: \(title)" : nil, color: spec.color, logo: spec.logo, icon: spec.icon,
                                 hostBundleId: t.bundleId, focus: .tab(bundleId: t.bundleId, url: t.url, title: t.title), signal: needs ? "title" : "none"))
            }
        }

        // Forget CPU samples of processes that are gone.
        let alive = Set(procs.map { $0.pid })
        cpuSamples = cpuSamples.filter { alive.contains($0.key) }
        return out
    }

    /// CPU seconds of a process plus its descendants (tools it is running), three levels deep.
    private func subtreeCPU(_ pid: pid_t, children: [pid_t: [pid_t]], depth: Int = 0) -> Double {
        var total = ProcessScanner.cpuTime(pid) ?? 0
        guard depth < 3, let kids = children[pid] else { return total }
        for k in kids { total += subtreeCPU(k, children: children, depth: depth + 1) }
        return total
    }

    // MARK: Publishing (main thread)

    static func fingerprint(_ a: Agent) -> String { "\(a.state.rawValue)|\(a.detail)|\(a.message ?? "")" }

    private func publish(_ found: [Agent], first: Bool) {
        guard demoAgents == nil else { return }
        var next: [Agent] = []
        var attention: [Agent] = []
        var states: [String: (state: Agent.State, since: Date)] = [:]
        for var a in found {
            if a.state == .waiting, acknowledged[a.id] == Self.fingerprint(a) {
                a.state = .idle; a.signal = "seen"
            } else if a.state != .waiting {
                acknowledged.removeValue(forKey: a.id)
            }
            if let prev = previousStates[a.id] {
                if prev.state == a.state { a.since = prev.since } else if a.state == .waiting { attention.append(a) }
            } else if a.state == .waiting, !first {
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
        queue.async {
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
            }
            DispatchQueue.main.async { done?(ok) }
        }
    }

    /// Marks an agent as seen (after you tap it) so the bar stops pulsing until something about it changes.
    public func acknowledge(_ id: String) {
        guard let i = agents.firstIndex(where: { $0.id == id }), agents[i].state == .waiting else { return }
        acknowledged[id] = Self.fingerprint(agents[i])
        agents[i].state = .idle
        agents[i].signal = "seen"
        previousStates[id] = (.idle, Date())
        onChange?()
    }

    // MARK: Demo data (README media, --snapshot agents:demo)

    public static func demoList() -> [Agent] {
        let now = Date()
        return [
            Agent(id: "d1", kind: .terminal, name: "Claude Code", detail: "widefive · Terminal", state: .waiting, since: now.addingTimeInterval(-40),
                  message: "Needs your permission to run swift test", color: "#d97757", logo: "web:claude.ai", icon: "sparkle",
                  hostBundleId: "com.apple.Terminal", focus: .terminal(bundleId: "com.apple.Terminal", tty: "ttys003", window: "widefive"), signal: "hook"),
            Agent(id: "d2", kind: .web, name: "Codex", detail: "(1) Add agent monitor — Codex", state: .waiting, since: now.addingTimeInterval(-12),
                  message: nil, color: "#10a37f", logo: "web:chatgpt.com", icon: "terminal", hostBundleId: "com.google.Chrome",
                  focus: .tab(bundleId: "com.google.Chrome", url: "https://chatgpt.com/codex", title: ""), signal: "title"),
            Agent(id: "d3", kind: .terminal, name: "Gemini CLI", detail: "api · iTerm2", state: .working, since: now.addingTimeInterval(-200),
                  message: nil, color: "#4285f4", logo: "web:gemini.google.com", icon: "diamond", hostBundleId: "com.googlecode.iterm2",
                  focus: .terminal(bundleId: "com.googlecode.iterm2", tty: "ttys005", window: nil), signal: "cpu"),
            Agent(id: "d4", kind: .app, name: "Cursor", detail: "landing-page", state: .working, since: now.addingTimeInterval(-90),
                  message: nil, color: "#8b5cf6", logo: "web:cursor.com", icon: "cursorarrow", hostBundleId: "com.todesktop.230313mzl4w4u92",
                  focus: .app(bundleId: "com.todesktop.230313mzl4w4u92", window: nil), signal: "hook"),
            Agent(id: "d5", kind: .web, name: "Claude Code", detail: "Touch Bar agent strip — Claude", state: .idle, since: now.addingTimeInterval(-300),
                  message: nil, color: "#d97757", logo: "web:claude.ai", icon: "sparkle", hostBundleId: "com.google.Chrome",
                  focus: .tab(bundleId: "com.google.Chrome", url: "https://claude.ai/code", title: ""), signal: "none"),
            Agent(id: "d6", kind: .app, name: "ChatGPT", detail: "ChatGPT", state: .idle, since: now.addingTimeInterval(-900),
                  message: nil, color: "#10a37f", logo: "web:chatgpt.com", icon: "bubble.left.fill", hostBundleId: "com.openai.chat",
                  focus: .app(bundleId: "com.openai.chat", window: nil), signal: "none"),
        ]
    }
}
