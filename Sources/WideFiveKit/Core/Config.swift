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
    /// button | widget | spacer | separator | slider
    public var kind: String
    public var title: String?
    /// SF Symbol name or emoji
    public var icon: String?
    /// hex color for the button background
    public var color: String?
    public var width: Double?
    public var action: Action?
    public var longPress: Action?
    /// widget name: clock, date, cpu, ram, battery, net, temp, fan, nowplaying, weather, pomodoro, disk, uptime, app
    /// slider target: volume, brightness
    public var name: String?

    enum CodingKeys: String, CodingKey { case kind = "type", title, icon, color, width, action, longPress, name }

    public init(kind: String, title: String? = nil, icon: String? = nil, color: String? = nil, width: Double? = nil,
                action: Action? = nil, longPress: Action? = nil, name: String? = nil) {
        self.kind = kind; self.title = title; self.icon = icon; self.color = color; self.width = width
        self.action = action; self.longPress = longPress; self.name = name
    }

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
    public var flickModes: Bool = true
    public init() {}
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
    public var flickOrder: [String] = ["home", "stats", "dock", "clipboard", "ambient"]

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
    }

    public func layout(for bundleId: String?) -> AppLayout? {
        guard let bundleId else { return nil }
        return apps.first { $0.bundleIds.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame } }
    }

    public static var `default`: Config { DefaultConfig.make() }

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
