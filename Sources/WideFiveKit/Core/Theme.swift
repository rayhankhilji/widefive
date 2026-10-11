import AppKit

/// A coherent palette + shape language. `button`/`buttonPressed`/`dim` are kept for older call sites;
/// new code should prefer the semantic aliases (`surface`, `surfaceHi`, `secondary`).
public struct Theme {
    public var name: String
    public var displayName: String
    public var background: NSColor
    /// Optional top colour: when set the strip background is a vertical gradient (top → `background`).
    public var backgroundTop: NSColor?
    public var button: NSColor
    public var buttonPressed: NSColor
    public var text: NSColor
    public var dim: NSColor
    public var accent: NSColor
    public var accent2: NSColor
    public var good: NSColor
    public var warn: NSColor
    public var bad: NSColor
    /// Corner radius for buttons, tiles and cards.
    public var radius: CGFloat
    /// 0 = flat, 1 = full neon bloom around accented elements.
    public var glow: CGFloat
    /// Light themes flip highlights/shadows.
    public var isLight: Bool

    public var surface: NSColor { button }
    public var surfaceHi: NSColor { buttonPressed }
    public var secondary: NSColor { dim }
    /// Hairline drawn around surfaces.
    public var stroke: NSColor { isLight ? NSColor(white: 0, alpha: 0.09) : NSColor(white: 1, alpha: 0.07) }
    /// Inner top highlight on surfaces.
    public var highlight: NSColor { isLight ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 1, alpha: 0.06) }
    /// Readable foreground for something filled with `color`.
    public func on(_ color: NSColor) -> NSColor { color.luminance > 0.55 ? NSColor(white: 0.06, alpha: 1) : .white }
    public var onAccent: NSColor { on(accent) }
    /// Colours for launcher tiles, cards and charts, derived from the palette so every theme stays coherent.
    public var spectrum: [NSColor] { [accent, accent2, good, warn, bad] }

    public init(name: String, displayName: String? = nil, background: NSColor, backgroundTop: NSColor? = nil, button: NSColor,
                buttonPressed: NSColor, text: NSColor, dim: NSColor, accent: NSColor, accent2: NSColor, good: NSColor,
                warn: NSColor, bad: NSColor, radius: CGFloat = 7, glow: CGFloat = 0.4, isLight: Bool = false) {
        self.name = name; self.displayName = displayName ?? name.capitalized
        self.background = background; self.backgroundTop = backgroundTop
        self.button = button; self.buttonPressed = buttonPressed; self.text = text; self.dim = dim
        self.accent = accent; self.accent2 = accent2; self.good = good; self.warn = warn; self.bad = bad
        self.radius = radius; self.glow = glow; self.isLight = isLight
    }

    private static func h(_ s: String) -> NSColor { NSColor(hex: s) }

    public static let neon = Theme(name: "neon", displayName: "Neon", background: h("#000000"), backgroundTop: h("#07051a"),
                                   button: h("#17142c"), buttonPressed: h("#2c2554"), text: .white, dim: h("#8f8cb4"),
                                   accent: h("#ff2bd6"), accent2: h("#21e6ff"), good: h("#39ff88"), warn: h("#ffd23f"), bad: h("#ff4d6d"),
                                   radius: 7, glow: 1)
    public static let graphite = Theme(name: "graphite", displayName: "Graphite Pro", background: h("#000000"),
                                       button: h("#2c2c2e"), buttonPressed: h("#4a4a4d"), text: h("#f5f5f7"), dim: h("#8e8e93"),
                                       accent: h("#0a84ff"), accent2: h("#64d2ff"), good: h("#30d158"), warn: h("#ffd60a"), bad: h("#ff453a"),
                                       radius: 7, glow: 0)
    public static let midnight = Theme(name: "midnight", displayName: "Midnight", background: h("#03050c"), backgroundTop: h("#0a1022"),
                                       button: h("#121b31"), buttonPressed: h("#20305a"), text: h("#e7eeff"), dim: h("#7e8db3"),
                                       accent: h("#7c9cff"), accent2: h("#5eead4"), good: h("#4ade80"), warn: h("#fbbf24"), bad: h("#f87171"),
                                       radius: 8, glow: 0.45)
    public static let sunset = Theme(name: "sunset", displayName: "Sunset", background: h("#0d0408"), backgroundTop: h("#24081a"),
                                     button: h("#2c1222"), buttonPressed: h("#53203d"), text: h("#fff0e4"), dim: h("#c0968f"),
                                     accent: h("#ff7a59"), accent2: h("#ffc46b"), good: h("#c6e46b"), warn: h("#ffb347"), bad: h("#ff3d6e"),
                                     radius: 9, glow: 0.6)
    public static let nord = Theme(name: "nord", displayName: "Nord", background: h("#1d2128"),
                                   button: h("#353c4a"), buttonPressed: h("#4c566a"), text: h("#eceff4"), dim: h("#97a2b6"),
                                   accent: h("#88c0d0"), accent2: h("#b48ead"), good: h("#a3be8c"), warn: h("#ebcb8b"), bad: h("#bf616a"),
                                   radius: 6, glow: 0)
    public static let dracula = Theme(name: "dracula", displayName: "Dracula", background: h("#16171d"),
                                      button: h("#282a36"), buttonPressed: h("#44475a"), text: h("#f8f8f2"), dim: h("#9aa0c7"),
                                      accent: h("#bd93f9"), accent2: h("#ff79c6"), good: h("#50fa7b"), warn: h("#f1fa8c"), bad: h("#ff5555"),
                                      radius: 7, glow: 0.5)
    public static let paper = Theme(name: "paper", displayName: "Paper", background: h("#efeae0"), backgroundTop: h("#f7f4ee"),
                                    button: h("#ffffff"), buttonPressed: h("#ddd6c8"), text: h("#1f1c17"), dim: h("#7d756a"),
                                    accent: h("#e0531f"), accent2: h("#2563c9"), good: h("#2f8f46"), warn: h("#d98a00"), bad: h("#c92a2a"),
                                    radius: 7, glow: 0, isLight: true)
    public static let matcha = Theme(name: "matcha", displayName: "Matcha", background: h("#070d08"), backgroundTop: h("#0f1a11"),
                                     button: h("#18261b"), buttonPressed: h("#2a412e"), text: h("#eef5e6"), dim: h("#90a890"),
                                     accent: h("#a7d36f"), accent2: h("#e9dcb0"), good: h("#7fd18b"), warn: h("#e9c46a"), bad: h("#e76f51"),
                                     radius: 10, glow: 0.3)
    public static let synthwave = Theme(name: "synthwave", displayName: "Synthwave", background: h("#12002a"), backgroundTop: h("#2d0b45"),
                                        button: h("#2a0f4c"), buttonPressed: h("#4c1a80"), text: h("#fff1fd"), dim: h("#b991dc"),
                                        accent: h("#f92aad"), accent2: h("#36f9f6"), good: h("#72f1b8"), warn: h("#fede5d"), bad: h("#fe4450"),
                                        radius: 6, glow: 1)
    public static let oled = Theme(name: "oled", displayName: "Mono OLED", background: h("#000000"),
                                   button: h("#141414"), buttonPressed: h("#303030"), text: .white, dim: h("#7c7c7c"),
                                   accent: .white, accent2: h("#a6a6a6"), good: h("#e6e6e6"), warn: h("#bdbdbd"), bad: .white,
                                   radius: 5, glow: 0)

    public static let all: [Theme] = [.neon, .graphite, .midnight, .sunset, .nord, .dracula, .paper, .matcha, .synthwave, .oled]

    /// Older config names keep working.
    static let aliases = ["mono": "oled", "ocean": "midnight", "retro": "matcha", "pro": "graphite", "light": "paper"]

    public static func named(_ name: String?) -> Theme {
        let n = name?.lowercased() ?? ""
        let id = aliases[n] ?? n
        return all.first { $0.name == id } ?? .neon
    }

    /// Maps a config/brand colour into the theme (mono themes collapse colour to the accent).
    public func tint(_ c: NSColor) -> NSColor {
        if name == "oled" { return accent }
        return isLight ? c.mix(.black, 0.12) : c
    }

    public func next(_ step: Int = 1) -> Theme {
        let i = Theme.all.firstIndex { $0.name == name } ?? 0
        return Theme.all[(i + step + Theme.all.count) % Theme.all.count]
    }
}

/// Shared spacing grid + type scale so every mode lines up.
public enum Metrics {
    public static let height: CGFloat = 30
    /// Gap between controls in a group.
    public static let gap: CGFloat = 5
    /// Gap between groups.
    public static let groupGap: CGFloat = 12
    /// Where content starts in modes that show the exit button.
    public static var contentX: CGFloat { StripController.exitWidth + 6 }
    public static let icon: CGFloat = 13
    public static let iconSmall: CGFloat = 11

    public enum Font {
        public static let caption: CGFloat = 8.5
        public static let label: CGFloat = 11
        public static let body: CGFloat = 12.5
        public static let title: CGFloat = 15
        public static let display: CGFloat = 18
    }
}

public extension NSColor {
    /// Relative luminance (sRGB), 0…1.
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    func mix(_ other: NSColor, _ t: CGFloat) -> NSColor {
        let t = max(0, min(1, t))
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }

    func alpha(_ a: CGFloat) -> NSColor { withAlphaComponent(a) }
}
