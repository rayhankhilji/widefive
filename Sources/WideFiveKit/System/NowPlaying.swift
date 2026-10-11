import AppKit

/// Now-playing info. Tries private MediaRemote first (works up to macOS 15.3), then AppleScript for Spotify / Music
/// (only queries apps that are already running, so it never launches them).
public final class NowPlaying {
    public static let shared = NowPlaying()

    public private(set) var title: String = ""
    public private(set) var artist: String = ""
    public private(set) var isPlaying = false
    public private(set) var artwork: NSImage?
    public private(set) var source: String = ""
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    public var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var artworkURL: String?
    private let queue = DispatchQueue(label: "widefive.nowplaying")

    private typealias MRGetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private let mrGetInfo: MRGetInfo? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let s = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
        return unsafeBitCast(s, to: MRGetInfo.self)
    }()

    public func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        if let mr = mrGetInfo {
            mr(queue) { [weak self] dict in
                guard let self else { return }
                let d = (dict as? [String: Any]) ?? [:]
                if let t = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !t.isEmpty {
                    let a = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                    let rate = d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
                    let img = (d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap(NSImage.init(data:))
                    let dur = d["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
                    let pos = d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
                    DispatchQueue.main.async {
                        self.apply(title: t, artist: a, playing: rate > 0, source: "system", duration: dur, position: pos)
                        if let img { self.artwork = img }
                    }
                } else {
                    self.pollAppleScript()
                }
            }
        } else {
            queue.async { self.pollAppleScript() }
        }
    }

    private func isRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private func pollAppleScript() {
        let candidates: [(String, String, String)] = [
            ("com.spotify.client", "Spotify", "artwork url of current track"),
            ("com.apple.Music", "Music", "\"\""),
        ]
        for (bid, name, art) in candidates where isRunning(bid) {
            let src = """
            tell application "\(name)"
                if player state is stopped then return ""
                set t to name of current track
                set a to artist of current track
                set s to (player state as text)
                set d to duration of current track
                set p to player position
                set u to \(art)
                return t & "\u{1F}" & a & "\u{1F}" & s & "\u{1F}" & d & "\u{1F}" & p & "\u{1F}" & u
            end tell
            """
            var err: NSDictionary?
            guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !out.isEmpty else { continue }
            let parts = out.components(separatedBy: "\u{1F}")
            guard parts.count >= 6 else { continue }
            var dur = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            if name == "Spotify" { dur /= 1000 }
            let pos = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            let url = parts[5]
            DispatchQueue.main.async {
                self.apply(title: parts[0], artist: parts[1], playing: parts[2] == "playing", source: name, duration: dur, position: pos)
                if !url.isEmpty, url != self.artworkURL { self.loadArtwork(url) }
                if url.isEmpty, name == "Music" { self.artwork = nil }
            }
            return
        }
        DispatchQueue.main.async { self.apply(title: "", artist: "", playing: false, source: "", duration: 0, position: 0) }
    }

    private func apply(title: String, artist: String, playing: Bool, source: String, duration: Double, position: Double) {
        let changed = title != self.title || playing != isPlaying
        self.title = title; self.artist = artist; isPlaying = playing; self.source = source
        self.duration = duration; self.position = position
        if title.isEmpty { artwork = nil; artworkURL = nil }
        if changed { onUpdate?() }
    }

    private func loadArtwork(_ s: String) {
        artworkURL = s
        guard let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self.artwork = img; self.onUpdate?() }
        }.resume()
    }
}

/// Current weather from wttr.in (no API key). Refreshes every 15 minutes.
public final class Weather {
    public static let shared = Weather()
    public private(set) var summary: String = ""
    public var location: String = ""
    private var last: Date?

    public func refreshIfNeeded() {
        if let last, Date().timeIntervalSince(last) < 900 { return }
        last = Date()
        let loc = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://wttr.in/\(loc)?format=%c%t") else { return }
        URLSession.shared.dataTask(with: url) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8), s.count < 40 else { return }
            DispatchQueue.main.async { self.summary = s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
        }.resume()
    }
}
