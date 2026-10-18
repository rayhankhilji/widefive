import Foundation

/// What the Touch Bar knows about one coding agent on this Mac.
public struct Agent: Equatable {
    public enum Kind: String, Codable { case terminal, app, web }
    public enum State: String, Codable {
        /// Busy: streaming, thinking or running tools.
        case working
        /// Stopped and waiting for you: a permission prompt, a question, or a finished turn.
        case waiting
        /// Running but nothing is happening (fresh session, agent app with no badge).
        case idle
    }

    /// How to bring it to the front when tapped.
    public enum Focus: Equatable {
        /// Plain app: activate it, optionally raise the window whose title contains `window`.
        case app(bundleId: String, window: String?)
        /// Terminal tab found by its tty (Terminal.app / iTerm2), falling back to activating the host app.
        case terminal(bundleId: String?, tty: String?, window: String?)
        /// Browser tab found by URL.
        case tab(bundleId: String, url: String, title: String)
    }

    public var id: String
    public var kind: Kind
    public var name: String
    /// Project folder, tab title or app name.
    public var detail: String
    public var state: State
    public var since: Date
    /// Why it's waiting ("Claude needs your permission to use Bash"), when known.
    public var message: String?
    /// Brand colour (hex).
    public var color: String
    /// LogoCache spec ("app:…|web:…") for the full-colour icon.
    public var logo: String?
    /// SF Symbol fallback.
    public var icon: String
    /// Where it's hosted: terminal app, browser or the app itself.
    public var hostBundleId: String?
    public var focus: Focus
    /// "hook", "cpu", "badge", "title" — which signal decided `state`.
    public var signal: String

    public init(id: String, kind: Kind, name: String, detail: String, state: State, since: Date = Date(), message: String? = nil,
                color: String, logo: String? = nil, icon: String, hostBundleId: String? = nil, focus: Focus, signal: String) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail; self.state = state; self.since = since
        self.message = message; self.color = color; self.logo = logo; self.icon = icon; self.hostBundleId = hostBundleId
        self.focus = focus; self.signal = signal
    }

    public var needsYou: Bool { state == .waiting }
}

/// The built-in list of agents widefive recognises, plus the user's additions from config.
public enum AgentCatalog {
    public struct Spec: Equatable {
        public var key: String
        public var name: String
        public var color: String
        public var logo: String?
        public var icon: String
        public init(key: String, name: String, color: String, logo: String? = nil, icon: String) {
            self.key = key; self.name = name; self.color = color; self.logo = logo; self.icon = icon
        }
    }

    // MARK: Terminal agents (matched on the executable / script name)

    public static let terminal: [Spec] = [
        Spec(key: "claude", name: "Claude Code", color: "#d97757", logo: "web:claude.ai", icon: "sparkle"),
        Spec(key: "codex", name: "Codex", color: "#10a37f", logo: "web:chatgpt.com", icon: "terminal"),
        Spec(key: "gemini", name: "Gemini CLI", color: "#4285f4", logo: "web:gemini.google.com", icon: "diamond"),
        Spec(key: "aider", name: "Aider", color: "#14b8a6", logo: "web:aider.chat", icon: "chevron.left.forwardslash.chevron.right"),
        Spec(key: "cursor-agent", name: "Cursor Agent", color: "#8b5cf6", logo: "web:cursor.com", icon: "cursorarrow"),
        Spec(key: "copilot", name: "Copilot CLI", color: "#8957e5", logo: "web:github.com", icon: "airplane"),
        Spec(key: "opencode", name: "OpenCode", color: "#f59e0b", logo: "web:opencode.ai", icon: "terminal"),
        Spec(key: "amp", name: "Amp", color: "#ef4444", logo: "web:ampcode.com", icon: "bolt"),
        Spec(key: "goose", name: "Goose", color: "#22c55e", logo: "web:block.github.io", icon: "bird"),
        Spec(key: "droid", name: "Factory Droid", color: "#6366f1", logo: "web:factory.ai", icon: "cpu"),
        Spec(key: "crush", name: "Crush", color: "#ec4899", logo: "web:charm.sh", icon: "heart"),
        Spec(key: "auggie", name: "Augment", color: "#06b6d4", logo: "web:augmentcode.com", icon: "plus.circle"),
        Spec(key: "kiro-cli", name: "Kiro CLI", color: "#a855f7", logo: "web:kiro.dev", icon: "leaf"),
        Spec(key: "cline", name: "Cline", color: "#3b82f6", logo: "web:cline.bot", icon: "line.3.horizontal"),
        Spec(key: "devin", name: "Devin", color: "#2563eb", logo: "web:devin.ai", icon: "person.crop.circle"),
        Spec(key: "qwen", name: "Qwen Code", color: "#7c3aed", logo: "web:qwen.ai", icon: "q.circle"),
        Spec(key: "rovodev", name: "Rovo Dev", color: "#0052cc", logo: "web:atlassian.com", icon: "r.circle"),
    ]

    /// Runtimes an agent script may run under (the script name is then in argv). Shells are deliberately not here.
    public static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "env", "npx", "pnpm", "uv", "uvx", "pipx"]

    /// Identifies an agent from a process's argv (plus the kernel's short name). Returns nil for anything else.
    public static func terminalSpec(arguments: [String], comm: String, extra: [String: String] = [:]) -> Spec? {
        var names: [String] = []
        if !comm.isEmpty { names.append(comm) }
        // argv[0] and the first script-looking arguments (node …/bin/codex.js, python -m aider).
        for a in arguments.prefix(4) {
            let base = (a as NSString).lastPathComponent
            if !base.isEmpty { names.append(base) }
        }
        let lowered = names.map { n -> String in
            var s = n.lowercased()
            for suffix in [".js", ".mjs", ".cjs", ".py", "-aarch64-apple-darwin", "-x86_64-apple-darwin"] where s.hasSuffix(suffix) {
                s.removeLast(suffix.count)
            }
            return s
        }
        for n in lowered {
            if let name = extra[n] { return Spec(key: n, name: name, color: "#64748b", icon: "terminal") }
            if let spec = terminal.first(where: { $0.key == n }) { return spec }
        }
        // Package names: node_modules/@anthropic-ai/claude-code, @openai/codex, @google/gemini-cli.
        let joined = arguments.prefix(4).joined(separator: " ").lowercased()
        if joined.contains("claude-code") { return terminal[0] }
        if joined.contains("@openai/codex") { return terminal[1] }
        if joined.contains("gemini-cli") { return terminal[2] }
        return nil
    }

    // MARK: Desktop apps

    public struct AppSpec: Equatable {
        public var bundleIds: [String]
        /// Matched against the app's display name when the bundle id is unknown (new apps, betas).
        public var names: [String]
        public var name: String
        public var color: String
        public var logo: String?
        public var icon: String
        /// Agent-first apps show whenever they run; editors/terminals only when they host an agent or carry a badge.
        public var standalone: Bool
    }

    public static let apps: [AppSpec] = [
        AppSpec(bundleIds: ["com.anthropic.claudefordesktop"], names: ["Claude"], name: "Claude", color: "#d97757", logo: "app:com.anthropic.claudefordesktop|web:claude.ai", icon: "sparkle", standalone: true),
        AppSpec(bundleIds: ["com.openai.chat"], names: ["ChatGPT"], name: "ChatGPT", color: "#10a37f", logo: "app:com.openai.chat|web:chatgpt.com", icon: "bubble.left.fill", standalone: true),
        AppSpec(bundleIds: ["com.openai.codex"], names: ["Codex"], name: "Codex", color: "#10a37f", logo: "app:com.openai.codex|web:chatgpt.com", icon: "terminal", standalone: true),
        AppSpec(bundleIds: ["ai.cognition.devin", "com.cognition.devin"], names: ["Devin"], name: "Devin", color: "#2563eb", logo: "web:devin.ai", icon: "person.crop.circle", standalone: true),
        AppSpec(bundleIds: ["ai.x.grok", "com.x.grok"], names: ["Grok"], name: "Grok", color: "#000000", logo: "web:grok.com", icon: "x.circle", standalone: true),
        AppSpec(bundleIds: ["com.todesktop.230313mzl4w4u92"], names: ["Cursor"], name: "Cursor", color: "#8b5cf6", logo: "app:com.todesktop.230313mzl4w4u92|web:cursor.com", icon: "cursorarrow", standalone: true),
        AppSpec(bundleIds: ["com.exafunction.windsurf"], names: ["Windsurf"], name: "Windsurf", color: "#0ea5e9", logo: "app:com.exafunction.windsurf|web:windsurf.com", icon: "wind", standalone: true),
        AppSpec(bundleIds: ["com.google.antigravity"], names: ["Antigravity"], name: "Antigravity", color: "#4285f4", logo: "web:antigravity.google", icon: "arrow.up.circle", standalone: true),
        AppSpec(bundleIds: ["dev.kiro.desktop"], names: ["Kiro"], name: "Kiro", color: "#a855f7", logo: "web:kiro.dev", icon: "leaf", standalone: true),
        AppSpec(bundleIds: ["com.trae.app"], names: ["Trae"], name: "Trae", color: "#ef4444", logo: "web:trae.ai", icon: "t.circle", standalone: true),
        AppSpec(bundleIds: ["com.github.copilot"], names: ["GitHub Copilot"], name: "Copilot", color: "#8957e5", logo: "web:github.com", icon: "airplane", standalone: true),
        // Hosts: shown when they carry a badge or run a terminal agent.
        AppSpec(bundleIds: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], names: ["Code", "Visual Studio Code"], name: "VS Code", color: "#007acc", logo: "app:com.microsoft.VSCode", icon: "chevron.left.forwardslash.chevron.right", standalone: false),
        AppSpec(bundleIds: ["dev.zed.Zed"], names: ["Zed"], name: "Zed", color: "#084ccf", logo: "app:dev.zed.Zed", icon: "z.circle", standalone: false),
        AppSpec(bundleIds: ["dev.warp.Warp-Stable", "dev.warp.Warp"], names: ["Warp"], name: "Warp", color: "#01a4ff", logo: "app:dev.warp.Warp-Stable", icon: "terminal", standalone: false),
        AppSpec(bundleIds: ["com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.WebStorm", "com.jetbrains.goland", "com.jetbrains.rider"], names: [], name: "JetBrains", color: "#fe2857", icon: "square.stack.3d.up", standalone: false),
    ]

    public static func appSpec(bundleId: String?, name: String?, extra: [String: String] = [:]) -> AppSpec? {
        if let b = bundleId {
            if let n = extra[b] { return AppSpec(bundleIds: [b], names: [], name: n, color: "#64748b", logo: "app:\(b)", icon: "app", standalone: true) }
            if let s = apps.first(where: { $0.bundleIds.contains { $0.caseInsensitiveCompare(b) == .orderedSame } }) { return s }
        }
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty,
           let s = apps.first(where: { $0.names.contains { $0.caseInsensitiveCompare(n) == .orderedSame } }) {
            return s
        }
        return nil
    }

    /// Terminal emulators and editors that can host an agent process. `tabs` → tabs can be selected by tty.
    public static let terminalHosts: [String: (name: String, tabs: Bool)] = [
        "com.apple.Terminal": ("Terminal", true),
        "com.googlecode.iterm2": ("iTerm2", true),
        "dev.warp.Warp-Stable": ("Warp", false),
        "dev.warp.Warp": ("Warp", false),
        "com.mitchellh.ghostty": ("Ghostty", false),
        "net.kovidgoyal.kitty": ("kitty", false),
        "org.alacritty": ("Alacritty", false),
        "com.github.wez.wezterm": ("WezTerm", false),
        "co.zeit.hyper": ("Hyper", false),
        "com.apple.dt.Xcode": ("Xcode", false),
    ]

    // MARK: Web agents (URL substrings, matched against browser tabs)

    public static let sites: [(match: String, spec: Spec)] = [
        ("claude.ai/code", Spec(key: "claude-web", name: "Claude Code", color: "#d97757", logo: "web:claude.ai", icon: "sparkle")),
        ("chatgpt.com/codex", Spec(key: "codex-web", name: "Codex", color: "#10a37f", logo: "web:chatgpt.com", icon: "terminal")),
        ("codex.openai.com", Spec(key: "codex-web", name: "Codex", color: "#10a37f", logo: "web:chatgpt.com", icon: "terminal")),
        ("app.devin.ai", Spec(key: "devin-web", name: "Devin", color: "#2563eb", logo: "web:devin.ai", icon: "person.crop.circle")),
        ("devin.ai/", Spec(key: "devin-web", name: "Devin", color: "#2563eb", logo: "web:devin.ai", icon: "person.crop.circle")),
        ("cursor.com/agents", Spec(key: "cursor-web", name: "Cursor Agent", color: "#8b5cf6", logo: "web:cursor.com", icon: "cursorarrow")),
        ("cursor.com/dashboard", Spec(key: "cursor-web", name: "Cursor Agent", color: "#8b5cf6", logo: "web:cursor.com", icon: "cursorarrow")),
        ("github.com/copilot", Spec(key: "copilot-web", name: "Copilot", color: "#8957e5", logo: "web:github.com", icon: "airplane")),
        ("jules.google.com", Spec(key: "jules", name: "Jules", color: "#4285f4", logo: "web:jules.google.com", icon: "j.circle")),
        ("gemini.google.com", Spec(key: "gemini-web", name: "Gemini", color: "#4285f4", logo: "web:gemini.google.com", icon: "diamond")),
        ("grok.com", Spec(key: "grok-web", name: "Grok", color: "#000000", logo: "web:grok.com", icon: "x.circle")),
        ("replit.com", Spec(key: "replit", name: "Replit", color: "#f26207", logo: "web:replit.com", icon: "r.circle")),
        ("lovable.dev", Spec(key: "lovable", name: "Lovable", color: "#ff4d8d", logo: "web:lovable.dev", icon: "heart")),
        ("bolt.new", Spec(key: "bolt", name: "Bolt", color: "#1389fd", logo: "web:bolt.new", icon: "bolt")),
        ("v0.app", Spec(key: "v0", name: "v0", color: "#000000", logo: "web:v0.app", icon: "v.circle")),
        ("v0.dev", Spec(key: "v0", name: "v0", color: "#000000", logo: "web:v0.dev", icon: "v.circle")),
        ("app.all-hands.dev", Spec(key: "openhands", name: "OpenHands", color: "#f59e0b", logo: "web:all-hands.dev", icon: "hand.raised")),
        ("app.factory.ai", Spec(key: "factory-web", name: "Factory", color: "#6366f1", logo: "web:factory.ai", icon: "cpu")),
        ("ona.com", Spec(key: "ona", name: "Ona", color: "#ff8a00", logo: "web:ona.com", icon: "o.circle")),
        ("windsurf.com/agents", Spec(key: "windsurf-web", name: "Windsurf", color: "#0ea5e9", logo: "web:windsurf.com", icon: "wind")),
        ("manus.im", Spec(key: "manus", name: "Manus", color: "#111827", logo: "web:manus.im", icon: "hand.point.up.left")),
    ]

    public static func siteSpec(url: String, extra: [String: String] = [:]) -> Spec? {
        let u = url.lowercased()
        guard u.hasPrefix("http"), let parsed = URL(string: u), var host = parsed.host else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = parsed.path.isEmpty ? "/" : parsed.path
        for (k, name) in extra where siteMatches(k.lowercased(), host: host, path: path) {
            return Spec(key: k, name: name, color: "#64748b", logo: "web:\(host)", icon: "globe")
        }
        return sites.first { siteMatches($0.match, host: host, path: path) }?.spec
    }

    /// "devin.ai/" matches app.devin.ai; "claude.ai/code" matches claude.ai/code/… but not a search URL that mentions it.
    static func siteMatches(_ pattern: String, host: String, path: String) -> Bool {
        let parts = pattern.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let domain = String(parts[0])
        let prefix = parts.count > 1 ? "/" + parts[1] : "/"
        guard host == domain || host.hasSuffix("." + domain) else { return false }
        return path == prefix || path.hasPrefix(prefix) || prefix == "/"
    }

    public static func domain(_ url: String) -> String? {
        guard let u = URL(string: url), var h = u.host else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h.isEmpty ? nil : h
    }

    /// Browsers whose tabs can be read over AppleScript. Safari uses a different dialect from the Chromium family.
    public static let browsers: [(bundleId: String, safari: Bool)] = [
        ("com.google.Chrome", false), ("com.google.Chrome.canary", false), ("com.google.Chrome.beta", false),
        ("com.brave.Browser", false), ("com.microsoft.edgemac", false), ("company.thebrowser.Browser", false),
        ("company.thebrowser.dia", false), ("com.vivaldi.Vivaldi", false), ("org.chromium.Chromium", false),
        ("ai.perplexity.comet", false), ("com.apple.Safari", true), ("com.apple.SafariTechnologyPreview", true),
    ]

    // MARK: "Needs you" from a tab or window title

    public static let defaultAttentionTitles: [String] = [
        #"^\(\d+\)"#, #"^[•●◉🔴🟠🟡🔵] "#,
        #"needs? (your )?(input|attention|approval|review|permission)"#,
        #"waiting (for|on) (you|your|input|approval)"#,
        #"(ready|awaiting|requires?) (for )?(your )?(review|approval|input)"#,
        #"permission (needed|required|request)"#, #"\bapprove\b"#, #"action required"#,
    ]

    public static func titleNeedsYou(_ title: String, patterns: [String]) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            if re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { return true }
        }
        return false
    }
}
