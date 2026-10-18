import Foundation

/// Built-in per-app layouts. Users edit ~/.widefive/config.json (generated from this on first launch).
enum DefaultConfig {
    static func chrome(_ url: String) -> Action { Action(shell: "open -a 'Google Chrome' '\(url)' || open '\(url)'") }

    /// Full-colour pinned launchers, shown in every app.
    static let pinnedApps: [Item] = [
        .logo("web:claude.ai|app:com.anthropic.claudefordesktop", fallback: "sparkle", color: "#d97757",
              Action(shell: "open -b com.anthropic.claudefordesktop || open -a Claude || open https://claude.ai")),
        .logo("web:outlook.live.com", fallback: "envelope.fill", color: "#0f6cbd", chrome("https://outlook.live.com/mail/")),
        .logo("web:linkedin.com", fallback: "person.crop.square.fill", color: "#0a66c2", chrome("https://www.linkedin.com/feed/")),
        .logo("web:chatgpt.com", fallback: "bubble.left.fill", color: "#10a37f", chrome("https://chatgpt.com/")),
        .logo("url:https://is1-ssl.mzstatic.com/image/thumb/Purple126/v4/66/fd/1f/66fd1fbd-eacf-2dab-8787-b528aba015f7/AppIcon-0-0-1x_U007emarketing-0-10-0-85-220.png/256x256bb.png|web:classcharts.com", fallback: "graduationcap.fill", color: "#4f46e5", chrome("https://www.classcharts.com/student/login")),
    ]

    static let controlButton = Item.button(nil, "slider.horizontal.3", Action(mode: "control"), color: "#21a6ff")

    static func make() -> Config {
        var c = Config()
        c.version = Config.currentVersion
        c.leading = [
            .button(nil, "square.grid.2x2.fill", Action(mode: "launcher"), color: "#ff2bd6"),
            controlButton,
        ] + pinnedApps
        c.trailing = [
            .button(nil, "camera.viewfinder", Action(keys: "cmd+shift+5"), color: "#8e8e93", longPress: Action(keys: "cmd+shift+4")),
            .quick("brightness"),
            .quick("keyboard"),
            .quick("volume"),
            .widget("agents"),
            .widget("battery"),
            .widget("clock"),
        ]
        c.defaultItems = [
            .widget("nowplaying", width: 170),
            .widget("weather"),
            .widget("cpu"),
            .widget("pomodoro"),
            .button(nil, "gamecontroller.fill", Action(mode: "plumber"), color: "#e63946"),
            .button(nil, "waveform", Action(mode: "visualizer")),
        ]
        c.apps = [
            AppLayout(name: "Spotify", bundleIds: ["com.spotify.client", "com.apple.Music"], items: [
                .button(nil, "backward.fill", Action(media: "prev")),
                .button(nil, "playpause.fill", Action(media: "playpause"), color: "#1db954"),
                .button(nil, "forward.fill", Action(media: "next")),
                .slider("volume", icon: "speaker.wave.2.fill"),
                .button(nil, "waveform", Action(mode: "visualizer")),
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
