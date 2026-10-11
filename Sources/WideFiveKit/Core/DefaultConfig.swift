import Foundation

/// Built-in per-app layouts. Users edit ~/.widefive/config.json (generated from this on first launch).
enum DefaultConfig {
    static func make() -> Config {
        var c = Config()
        c.leading = [
            .button(nil, "square.grid.2x2.fill", Action(mode: "launcher"), color: "#ff2bd6"),
            .widget("app"),
        ]
        c.trailing = [
            .widget("nowplaying", width: 170),
            .widget("cpu"),
            .widget("temp"),
            .widget("battery"),
            .widget("clock"),
        ]
        c.defaultItems = [
            .button(nil, "gamecontroller.fill", Action(mode: "plumber"), color: "#e63946"),
            .button(nil, "pianokeys", Action(mode: "piano")),
            .button(nil, "waveform", Action(mode: "visualizer")),
            .button(nil, "sparkles", Action(mode: "ambient")),
            .button(nil, "doc.on.clipboard", Action(mode: "clipboard")),
            .widget("pomodoro"),
            .slider("volume", icon: "speaker.wave.2.fill"),
            .slider("brightness", icon: "sun.max.fill"),
        ]
        let editorItems: [Item] = [
            .button("Palette", "command", Action(keys: "cmd+shift+p")),
            .button("Files", "doc.text.magnifyingglass", Action(keys: "cmd+p")),
            .button("Term", "terminal", Action(keys: "ctrl+`")),
            .button("Run", "play.fill", Action(keys: "f5"), color: "#2a9d8f", longPress: Action(keys: "shift+f5")),
            .button("Fmt", "text.alignleft", Action(keys: "shift+alt+f")),
            .button(nil, "number", Action(keys: "cmd+/")),
            .button(nil, "rectangle.split.2x1", Action(keys: "cmd+\\")),
            .button("Git", "arrow.triangle.branch", Action(keys: "ctrl+shift+g")),
            .button("Zen", "moon.fill", Action(keys: "cmd+k, z")),
        ]
        c.apps = [
            AppLayout(name: "VS Code", bundleIds: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.vscodium"],
                      items: editorItems, passthrough: nil, mode: nil),
            AppLayout(name: "Xcode", bundleIds: ["com.apple.dt.Xcode"], items: [
                .button("Build", "hammer.fill", Action(keys: "cmd+b")),
                .button("Run", "play.fill", Action(keys: "cmd+r"), color: "#2a9d8f"),
                .button("Stop", "stop.fill", Action(keys: "cmd+."), color: "#e63946"),
                .button("Test", "checkmark.diamond", Action(keys: "cmd+u")),
                .button("Clean", "trash", Action(keys: "cmd+shift+k")),
                .button("Open", "doc.text.magnifyingglass", Action(keys: "cmd+shift+o")),
                .button("Preview", "eye", Action(keys: "cmd+alt+return")),
                .button("Sim", "iphone", Action(open: "com.apple.iphonesimulator")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Terminal", bundleIds: ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty"], items: [
                .button("clear", "eraser", Action(keys: "cmd+k")),
                .button("tab", "plus.square.on.square", Action(keys: "cmd+t")),
                .button("git st", "arrow.triangle.branch", Action(type: "git status", submit: true)),
                .button("pull", "arrow.down.circle", Action(type: "git pull", submit: true)),
                .button("ls", "list.bullet", Action(type: "ls -la", submit: true)),
                .button("top", "chart.bar", Action(type: "top -o cpu", submit: true)),
                .button("^C", "xmark.octagon", Action(keys: "ctrl+c"), color: "#e63946"),
                .button(nil, "arrow.up", Action(keys: "up")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Browser", bundleIds: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"], items: [
                .button(nil, "chevron.left", Action(keys: "cmd+[")),
                .button(nil, "chevron.right", Action(keys: "cmd+]")),
                .button(nil, "arrow.clockwise", Action(keys: "cmd+r")),
                .button("Tab", "plus", Action(keys: "cmd+t")),
                .button("Reopen", "arrow.uturn.backward", Action(keys: "cmd+shift+t")),
                .button("DevTools", "chevron.left.forwardslash.chevron.right", Action(keys: "cmd+alt+i")),
                .button("Private", "eyeglasses", Action(keys: "cmd+shift+n")),
                .button("localhost", "server.rack", Action(url: "http://localhost:3000")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Spotify", bundleIds: ["com.spotify.client", "com.apple.Music"], items: [
                .button(nil, "backward.fill", Action(media: "prev")),
                .button(nil, "playpause.fill", Action(media: "playpause"), color: "#1db954"),
                .button(nil, "forward.fill", Action(media: "next")),
                .slider("volume", icon: "speaker.wave.2.fill"),
                .button(nil, "waveform", Action(mode: "visualizer")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Finder", bundleIds: ["com.apple.finder"], items: [
                .button("Folder", "folder.badge.plus", Action(keys: "cmd+shift+n")),
                .button("Hidden", "eye.slash", Action(keys: "cmd+shift+.")),
                .button("Info", "info.circle", Action(keys: "cmd+i")),
                .button("Term here", "terminal", Action(applescript: """
                    tell application "Finder" to set p to POSIX path of (insertion location as alias)
                    tell application "Terminal"
                        activate
                        do script "cd " & quoted form of p
                    end tell
                    """)),
                .button("Downloads", "arrow.down.circle", Action(keys: "cmd+alt+l")),
                .button("Empty Trash", "trash", Action(applescript: "tell application \"Finder\" to empty trash"), color: "#e63946"),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Slack", bundleIds: ["com.tinyspeck.slackmacgap", "com.hnc.Discord"], items: [
                .button("Jump", "magnifyingglass", Action(keys: "cmd+k")),
                .button("Unreads", "tray.full", Action(keys: "cmd+shift+a")),
                .button("Threads", "text.bubble", Action(keys: "cmd+shift+t")),
                .button("Read all", "checkmark.circle", Action(keys: "shift+escape")),
                .button("🚀", nil, Action(type: ":rocket:")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Figma", bundleIds: ["com.figma.Desktop"], items: [
                .button("Move", "cursorarrow", Action(keys: "v")),
                .button("Frame", "number.square", Action(keys: "f")),
                .button("Rect", "rectangle", Action(keys: "r")),
                .button("Text", "textformat", Action(keys: "t")),
                .button("Pen", "pencil.tip", Action(keys: "p")),
                .button("Comp", "square.on.square", Action(keys: "cmd+alt+k")),
                .button("Auto", "square.grid.3x1.below.line.grid.1x2", Action(keys: "shift+a")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Zoom", bundleIds: ["us.zoom.xos", "com.microsoft.teams2"], items: [
                .button("Mute", "mic.slash.fill", Action(keys: "cmd+shift+a"), color: "#e63946"),
                .button("Video", "video.slash.fill", Action(keys: "cmd+shift+v")),
                .button("Share", "rectangle.on.rectangle", Action(keys: "cmd+shift+s")),
                .button("Hand", "hand.raised.fill", Action(keys: "alt+y")),
            ], passthrough: nil, mode: nil),
            AppLayout(name: "Final Cut", bundleIds: ["com.apple.FinalCut", "com.apple.logic10"], items: [], passthrough: true, mode: nil),
        ]
        return c
    }
}
