import AppKit

public struct Theme {
    public var name: String
    public var background: NSColor
    public var button: NSColor
    public var buttonPressed: NSColor
    public var text: NSColor
    public var dim: NSColor
    public var accent: NSColor
    public var accent2: NSColor
    public var good: NSColor
    public var warn: NSColor
    public var bad: NSColor

    public static let neon = Theme(name: "neon", background: .black, button: NSColor(hex: "#1b1b2f"), buttonPressed: NSColor(hex: "#3a2d6b"),
                                   text: .white, dim: NSColor(hex: "#8a8aa8"), accent: NSColor(hex: "#ff2bd6"), accent2: NSColor(hex: "#21e6ff"),
                                   good: NSColor(hex: "#39ff88"), warn: NSColor(hex: "#ffd23f"), bad: NSColor(hex: "#ff4d5e"))
    public static let mono = Theme(name: "mono", background: .black, button: NSColor(hex: "#262626"), buttonPressed: NSColor(hex: "#4a4a4a"),
                                   text: .white, dim: NSColor(hex: "#8c8c8c"), accent: .white, accent2: NSColor(hex: "#bdbdbd"),
                                   good: NSColor(hex: "#d9d9d9"), warn: NSColor(hex: "#bdbdbd"), bad: NSColor(hex: "#ffffff"))
    public static let sunset = Theme(name: "sunset", background: NSColor(hex: "#120712"), button: NSColor(hex: "#2d1426"), buttonPressed: NSColor(hex: "#5a2340"),
                                     text: NSColor(hex: "#ffe9d6"), dim: NSColor(hex: "#b48a8a"), accent: NSColor(hex: "#ff7b54"), accent2: NSColor(hex: "#ffb26b"),
                                     good: NSColor(hex: "#ffd56b"), warn: NSColor(hex: "#ff9f45"), bad: NSColor(hex: "#ff3d68"))
    public static let retro = Theme(name: "retro", background: NSColor(hex: "#0f380f"), button: NSColor(hex: "#306230"), buttonPressed: NSColor(hex: "#8bac0f"),
                                    text: NSColor(hex: "#9bbc0f"), dim: NSColor(hex: "#8bac0f"), accent: NSColor(hex: "#9bbc0f"), accent2: NSColor(hex: "#8bac0f"),
                                    good: NSColor(hex: "#9bbc0f"), warn: NSColor(hex: "#8bac0f"), bad: NSColor(hex: "#9bbc0f"))
    public static let ocean = Theme(name: "ocean", background: NSColor(hex: "#020c1b"), button: NSColor(hex: "#0b2545"), buttonPressed: NSColor(hex: "#13315c"),
                                    text: NSColor(hex: "#e0f4ff"), dim: NSColor(hex: "#7d9bb8"), accent: NSColor(hex: "#64ffda"), accent2: NSColor(hex: "#48cae4"),
                                    good: NSColor(hex: "#64ffda"), warn: NSColor(hex: "#ffd166"), bad: NSColor(hex: "#ef476f"))

    public static let all: [Theme] = [.neon, .mono, .sunset, .retro, .ocean]

    public static func named(_ name: String?) -> Theme {
        all.first { $0.name == name?.lowercased() } ?? .neon
    }
}
