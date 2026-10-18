import Foundation

public struct Action: Codable, Equatable {
    /// "cmd+shift+p" — comma-separated for chords: "cmd+k, z"
    public var keys: String?
    /// Run via /bin/zsh -lc
    public var shell: String?
    public var applescript: String?
    public var url: String?
    /// Bundle id or app name to open/activate
    public var open: String?
    /// Switch to a mode id ("plumber", "launcher", ...)
    public var mode: String?
    /// playpause | next | prev | volup | voldown | mute | brightup | brightdown
    public var media: String?
    /// Types a string (followed by return if `submit`)
    public var type: String?
    public var submit: Bool?
    /// Show the output of `shell` / `applescript` as a toast
    public var showOutput: Bool?

    public init(keys: String? = nil, shell: String? = nil, applescript: String? = nil, url: String? = nil, open: String? = nil,
                mode: String? = nil, media: String? = nil, type: String? = nil, submit: Bool? = nil, showOutput: Bool? = nil) {
        self.keys = keys; self.shell = shell; self.applescript = applescript; self.url = url; self.open = open
        self.mode = mode; self.media = media; self.type = type; self.submit = submit; self.showOutput = showOutput
    }
}

public struct Item: Codable, Equatable {
    /// button | widget | spacer | separator | slider | quick (brightness / keyboard / volume, tap → full slider)
    public var kind: String
    public var title: String?
    /// SF Symbol name or emoji
    public var icon: String?
    /// hex color for the button background
    public var color: String?
    public var width: Double?
    public var action: Action?
    public var longPress: Action?
    /// widget name: clock, date, cpu, ram, battery, net, temp, fan, nowplaying, weather, pomodoro, disk, uptime, app, agents
    /// slider target: volume, brightness
    public var name: String?
    /// Full-colour logo instead of the SF Symbol: "app:<bundle id>" or "web:<domain>", fallbacks joined with "|".
    public var image: String?

    enum CodingKeys: String, CodingKey { case kind = "type", title, icon, color, width, action, longPress, name, image }

    public init(kind: String, title: String? = nil, icon: String? = nil, color: String? = nil, width: Double? = nil,
                action: Action? = nil, longPress: Action? = nil, name: String? = nil, image: String? = nil) {
        self.kind = kind; self.title = title; self.icon = icon; self.color = color; self.width = width
        self.action = action; self.longPress = longPress; self.name = name; self.image = image
    }

    public static func logo(_ image: String, fallback icon: String, color: String, _ action: Action) -> Item {
        Item(kind: "button", icon: icon, color: color, width: 44, action: action, image: image)
    }
    public static func quick(_ name: String) -> Item { Item(kind: "quick", width: 44, name: name) }

    public static func button(_ title: String?, _ icon: String?, _ action: Action, color: String? = nil, longPress: Action? = nil) -> Item {
        Item(kind: "button", title: title, icon: icon, color: color, action: action, longPress: longPress)
    }
    public static func widget(_ name: String, width: Double? = nil) -> Item { Item(kind: "widget", width: width, name: name) }
    public static func slider(_ name: String, icon: String) -> Item { Item(kind: "slider", icon: icon, width: 150, name: name) }
    public static let spacer = Item(kind: "spacer")
    public static let separator = Item(kind: "separator")
}

public struct AppLayout: Codable, Equatable {
    public var name: String
    public var bundleIds: [String]
    public var items: [Item]
    /// Hand the Touch Bar back to the app (e.g. Final Cut, Logic) while it is frontmost.
    public var passthrough: Bool?
    /// Switch to this mode automatically when the app becomes frontmost.
    public var mode: String?
}

public struct GestureConfig: Codable, Equatable {
    public var enabled: Bool = true
    public var twoFingerVolume: Bool = true
    public var threeFingerBrightness: Bool = true
    public var twoFingerTapPlayPause: Bool = true
    public var edgeSwipeLauncher: Bool = true
    public var flickModes: Bool = false
    public init() {}
}

/// Coding-agent monitor (the `agents` widget + Agents mode). See README → "Coding agents on the bar".
public struct AgentsConfig: Codable, Equatable {
    public var enabled: Bool = true
    /// Show a toast on the bar the moment an agent starts waiting for you.
    public var toast: Bool = true
    /// Also play a short sound.
    public var sound: Bool = false
    /// Seconds a terminal agent's process tree must sit at ~0% CPU before it counts as waiting (agents without hooks).
    public var idleSeconds: Double = 6
    /// Look through Chrome/Safari/Arc/Brave/Edge tabs for web agents (asks for Automation permission once per browser).
    public var scanBrowsers: Bool = true
    /// Extra terminal agents: executable or script name → display name, e.g. { "myagent": "My Agent" }.
    public var processes: [String: String] = [:]
    /// Extra desktop apps: bundle id → display name.
    public var apps: [String: String] = [:]
    /// Extra web agents: URL substring → display name, e.g. { "app.example.com/agents": "Example" }.
    public var sites: [String: String] = [:]
    /// Regular expressions; a browser tab whose title matches counts as needing you. Empty = built-in list.
    public var attentionTitles: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AgentsConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        toast = try c.decodeIfPresent(Bool.self, forKey: .toast) ?? d.toast
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? d.sound
        idleSeconds = try c.decodeIfPresent(Double.self, forKey: .idleSeconds) ?? d.idleSeconds
        scanBrowsers = try c.decodeIfPresent(Bool.self, forKey: .scanBrowsers) ?? d.scanBrowsers
        processes = try c.decodeIfPresent([String: String].self, forKey: .processes) ?? [:]
        apps = try c.decodeIfPresent([String: String].self, forKey: .apps) ?? [:]
        sites = try c.decodeIfPresent([String: String].self, forKey: .sites) ?? [:]
        attentionTitles = try c.decodeIfPresent([String].self, forKey: .attentionTitles) ?? []
    }
}

public struct Config: Codable, Equatable {
    public var theme: String = "neon"
    public var hideControlStrip: Bool = true
    public var replaceEscKey: Bool = false
    public var startMode: String = "home"
    public var stripWidth: Double?
    public var gestures: GestureConfig = GestureConfig()
    public var leading: [Item] = []
    public var trailing: [Item] = []
    public var defaultItems: [Item] = []
    public var apps: [AppLayout] = []
    public var pomodoroMinutes: Double = 25
    public var weatherLocation: String = ""
    public var flickOrder: [String] = ["home", "control", "stats", "dock", "clipboard", "ambient"]
    /// Hide the menu-bar icon (⌃⌥⌘M brings the menu back temporarily).
    public var hideMenuBarIcon: Bool = false
    public var agents: AgentsConfig = AgentsConfig()
    /// Schema version, used to migrate older config files forward.
    public var version: Int = 1

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
        hideControlStrip = try c.decodeIfPresent(Bool.self, forKey: .hideControlStrip) ?? d.hideControlStrip
        replaceEscKey = try c.decodeIfPresent(Bool.self, forKey: .replaceEscKey) ?? d.replaceEscKey
        startMode = try c.decodeIfPresent(String.self, forKey: .startMode) ?? d.startMode
        stripWidth = try c.decodeIfPresent(Double.self, forKey: .stripWidth)
        gestures = try c.decodeIfPresent(GestureConfig.self, forKey: .gestures) ?? d.gestures
        leading = try c.decodeIfPresent([Item].self, forKey: .leading) ?? []
        trailing = try c.decodeIfPresent([Item].self, forKey: .trailing) ?? []
        defaultItems = try c.decodeIfPresent([Item].self, forKey: .defaultItems) ?? []
        apps = try c.decodeIfPresent([AppLayout].self, forKey: .apps) ?? []
        pomodoroMinutes = try c.decodeIfPresent(Double.self, forKey: .pomodoroMinutes) ?? d.pomodoroMinutes
        weatherLocation = try c.decodeIfPresent(String.self, forKey: .weatherLocation) ?? d.weatherLocation
        flickOrder = try c.decodeIfPresent([String].self, forKey: .flickOrder) ?? d.flickOrder
        hideMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? d.hideMenuBarIcon
        agents = try c.decodeIfPresent(AgentsConfig.self, forKey: .agents) ?? d.agents
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func layout(for bundleId: String?) -> AppLayout? {
        guard let bundleId else { return nil }
        return apps.first { $0.bundleIds.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame } }
    }

    public static var `default`: Config { DefaultConfig.make() }
    public static let currentVersion = 5

    /// v1 → v2: adds the Controls button next to the launcher and turns off mode-flicking (it fought with scrolling).
    public static func migrate(_ old: Config) -> Config {
        var c = old
        if c.version < 2 {
            if !c.leading.contains(where: { $0.action?.mode == "control" }) {
                let at = c.leading.firstIndex { $0.action?.mode == "launcher" }.map { $0 + 1 } ?? 0
                c.leading.insert(DefaultConfig.controlButton, at: at)
            }
            c.gestures.flickModes = false
            if !c.flickOrder.contains("control") { c.flickOrder.insert("control", at: min(1, c.flickOrder.count)) }
        }
        // v3: new home bar (pinned app logos, screenshot, Apple-style quick controls). Old file is backed up on load.
        if c.version < 3 {
            let d = DefaultConfig.make()
            c.leading = d.leading; c.trailing = d.trailing; c.defaultItems = d.defaultItems; c.apps = d.apps
        }
        // v4: colour Claude logo, ClassCharts, live widgets in the middle.
        if c.version < 4 {
            let d = DefaultConfig.make()
            c.leading = d.leading; c.defaultItems = d.defaultItems
        }
        // v5: coding-agent strip in the trailing group (Claude Code, Codex, Cursor, web agents… tap to bring to front).
        if c.version < 5, !c.hasWidget("agents") {
            let at = c.trailing.firstIndex { $0.kind == "widget" } ?? c.trailing.count
            c.trailing.insert(.widget("agents"), at: at)
        }
        c.version = currentVersion
        return c
    }

    /// True when any group of the home bar contains the named widget.
    public func hasWidget(_ name: String) -> Bool {
        (leading + trailing + defaultItems + apps.flatMap { $0.items }).contains { $0.kind == "widget" && $0.name?.lowercased() == name }
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}

/// Loads ~/.widefive/config.json, writes defaults on first run, hot-reloads on change.
public final class ConfigStore {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".widefive")
    public static let file = directory.appendingPathComponent("config.json")

    public private(set) var config: Config = .default
    public private(set) var lastError: String?
    public var onChange: ((Config) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    public init() {}

    public func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Self.file.path), let data = try? Config.default.encoded() {
            try? data.write(to: Self.file)
        }
        do {
            let data = try Data(contentsOf: Self.file)
            config = try Config.decode(data)
            lastError = nil
            if config.version < Config.currentVersion {
                try? data.write(to: Self.directory.appendingPathComponent("config.v\(config.version).backup.json"))
                config = Config.migrate(config)
                if let out = try? config.encoded() { try? out.write(to: Self.file) }
            }
        } catch {
            lastError = "config.json: \(error.localizedDescription)"
            NSLog("widefive: \(lastError!) — \(error)")
        }
    }

    public func watch() {
        source?.cancel()
        fd = open(Self.file.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // Editors often save via rename; re-arm the watcher.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.load()
                self.onChange?(self.config)
                if flags.contains(.rename) || flags.contains(.delete) { self.watch() }
            }
        }
        let capturedFd = fd
        src.setCancelHandler { close(capturedFd) }
        src.resume()
        source = src
    }

    public func resetToDefaults() {
        if let data = try? Config.default.encoded() { try? data.write(to: Self.file) }
    }
}
