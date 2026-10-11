import AppKit

enum Pal {
    static let red = NSColor(hex: "#e52521"), skin = NSColor(hex: "#f8b878"), hair = NSColor(hex: "#6b3e1e")
    static let blue = NSColor(hex: "#2038ec"), yellow = NSColor(hex: "#fbd000"), white = NSColor.white, black = NSColor.black
    static let brown = NSColor(hex: "#a0522d"), dark = NSColor(hex: "#3b1f0e"), green = NSColor(hex: "#43b047"), lgreen = NSColor(hex: "#8ce68c")
    static let sky = NSColor(hex: "#5c94fc"), orange = NSColor(hex: "#f87c00"), grey = NSColor(hex: "#8c8c8c"), pink = NSColor(hex: "#ff8ad8")
    static let cyan = NSColor(hex: "#21e6ff"), magenta = NSColor(hex: "#ff2bd6"), purple = NSColor(hex: "#7b2cff")
}

enum Sprites {
    static let hero: [Character: NSColor] = ["R": Pal.red, "S": Pal.skin, "H": Pal.hair, "B": Pal.blue, "Y": Pal.yellow, "K": Pal.black]

    static let smallStand = Sprite([
        "..RRRR.",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "..BRRB.",
        ".BBYBB.",
        ".HH.HH.",
    ], hero)
    static let smallRun = Sprite([
        "..RRRR.",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "S.BRRB.",
        ".BBYBBS",
        "HH...HH",
    ], hero)
    static let smallJump = Sprite([
        "..RRRRS",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "SBBRRB.",
        ".BBYBB.",
        "HH..HH.",
    ], hero)
    static let bigStand = Sprite([
        "..RRRR.",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        ".RRBRR.",
        "RRRBRRR",
        "S.BYB.S",
        ".BB.BB.",
        ".HH.HH.",
    ], hero)
    static let bigRun = Sprite([
        "..RRRR.",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        ".RRBRRS",
        "SRRBRR.",
        "..BYB..",
        ".BB.BB.",
        "HH...HH",
    ], hero)
    static let bigJump = Sprite([
        "..RRRRS",
        ".RRRRRR",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        "SRRBRR.",
        ".RRBRR.",
        "..BYB..",
        "BB..BB.",
        "H....H.",
    ], hero)

    static let goomba1 = Sprite([
        "..BB..",
        ".BBBB.",
        "BWKKWB",
        "BBBBBB",
        ".SSSS.",
        "KK..KK",
    ], ["B": Pal.brown, "W": Pal.white, "K": Pal.black, "S": Pal.skin])
    static let goomba2 = Sprite([
        "..BB..",
        ".BBBB.",
        "BWKKWB",
        "BBBBBB",
        ".SSSS.",
        ".KKKK.",
    ], ["B": Pal.brown, "W": Pal.white, "K": Pal.black, "S": Pal.skin])
    static let goombaFlat = Sprite([
        ".BBBB.",
        "BWKKWB",
    ], ["B": Pal.brown, "W": Pal.white, "K": Pal.black])
    static let spiky = Sprite([
        "W.W.W.",
        "RRRRRR",
        "RWKRWR",
        "RRRRRR",
        ".SSSS.",
        "KK..KK",
    ], ["R": Pal.red, "W": Pal.white, "K": Pal.black, "S": Pal.skin])

    static let coin = Sprite([".Y.", "YWY", "YWY", "YWY", ".Y."], ["Y": Pal.yellow, "W": NSColor(hex: "#fff2a8")])
    static let coinThin = Sprite(["Y", "W", "W", "W", "Y"], ["Y": Pal.yellow, "W": NSColor(hex: "#fff2a8")])
    static let mushroom = Sprite([".RRR.", "RWRWR", "RRRRR", ".SKS.", ".SSS."], ["R": Pal.red, "W": Pal.white, "S": Pal.skin, "K": Pal.black])
    static let star = Sprite(["..Y..", ".YYY.", "YKYKY", ".YYY.", "Y...Y"], ["Y": Pal.yellow, "K": Pal.black])
    static let gem = Sprite([".C.", "CWC", "CCC", ".C."], ["C": Pal.cyan, "W": Pal.white])

    static let runner = Sprite([
        ".MMM.",
        "MWKWM",
        "MMMMM",
        ".CCC.",
        "C.C.C",
        ".C.C.",
    ], ["M": Pal.magenta, "W": Pal.white, "K": Pal.black, "C": Pal.cyan])
    static let runner2 = Sprite([
        ".MMM.",
        "MWKWM",
        "MMMMM",
        ".CCC.",
        "C.C.C",
        "C...C",
    ], ["M": Pal.magenta, "W": Pal.white, "K": Pal.black, "C": Pal.cyan])

    static let cat = Sprite([
        "..PPPPPPPP..",
        ".PKPPPPPPKP.",
        "KPPPGGGGPPPK",
        "KPPGGKGKGPPK",
        "KPPGGGGGGPPK",
        "KPPGPGGPGPPK",
        ".KPPPPPPPPK.",
        "..K.K..K.K..",
    ], ["P": Pal.pink, "K": NSColor(hex: "#222222"), "G": Pal.grey])
    static let catHappy = Sprite([
        "..PPPPPPPP..",
        ".PKPPPPPPKP.",
        "KPPPGGGGPPPK",
        "KPPGKGGKGPPK",
        "KPPGGRRGGPPK",
        "KPPGGGGGGPPK",
        ".KPPPPPPPPK.",
        ".K..K..K..K.",
    ], ["P": Pal.pink, "K": NSColor(hex: "#222222"), "G": Pal.grey, "R": Pal.red])
    static let catSleep = Sprite([
        "............",
        "..PPPPPPPP..",
        ".PKPPPPPPKP.",
        "KPPPGGGGPPPK",
        "KPPGKKGKKPPK",
        "KPPGGGGGGPPK",
        ".KPPPPPPPPK.",
        "..KKKKKKKK..",
    ], ["P": Pal.pink, "K": NSColor(hex: "#222222"), "G": Pal.grey])
    static let bird = Sprite([
        "..YYYY..",
        ".YYYWKY.",
        "WWYYWWYO",
        "WWWYYYOO",
        ".YYYYYY.",
        "..YYYY..",
    ], ["Y": Pal.yellow, "W": Pal.white, "K": Pal.black, "O": Pal.orange])
    static let ship = Sprite([
        "CC........",
        "CCCC......",
        ".WWWWWCC..",
        "RWWWWWWWCC",
        ".WWWWWCC..",
        "CCCC......",
        "CC........",
    ], ["C": Pal.cyan, "W": NSColor(hex: "#d0d8ff"), "R": Pal.orange])
    static let foe = Sprite([
        "...WWW..",
        ".WWWWWW.",
        "WWKWWKWW",
        "WWWWWWWW",
        ".W.WW.W.",
        "W......W",
    ], ["W": Pal.white, "K": Pal.black])
}

/// Programmatic tile art.
enum TileArt {
    static func draw(_ c: Canvas, _ t: Tile, x: CGFloat, y: CGFloat, time: Double, night: Bool = false) {
        let T = TileWorld.T
        let r = CGRect(x: x, y: y, width: T, height: T)
        switch t {
        case .ground:
            c.fill(r, night ? NSColor(hex: "#2a1b4a") : Pal.brown)
            c.fill(CGRect(x: x, y: y + T - 1, width: T, height: 1), night ? Pal.purple : NSColor(hex: "#d07a3c"))
            c.fill(CGRect(x: x + 1, y: y + 1, width: 1, height: 1), NSColor(white: 0, alpha: 0.25))
        case .brick:
            c.fill(r, NSColor(hex: "#b85c1c"))
            c.fill(CGRect(x: x, y: y + 2, width: T, height: 0.6), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x + 2, y: y + 2.5, width: 0.6, height: 2.5), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x, y: y + T - 0.6, width: T, height: 0.6), NSColor(hex: "#e08a4c"))
        case .question:
            let glow = 0.75 + 0.25 * sin(time * 5)
            c.fill(r, NSColor(hex: "#f8b800").blended(withFraction: CGFloat(1 - glow), of: NSColor(hex: "#a05000"))!)
            c.fill(CGRect(x: x + 2, y: y + 1, width: 1, height: 0.8), Pal.dark)
            c.fill(CGRect(x: x + 2, y: y + 2.2, width: 1, height: 0.8), Pal.dark)
            c.fill(CGRect(x: x + 1.4, y: y + 3.4, width: 2.2, height: 0.8), Pal.dark)
        case .used:
            c.fill(r, NSColor(hex: "#8a5a2a"))
            c.fill(r.insetBy(dx: 1.2, dy: 1.2), NSColor(hex: "#6a4220"))
        case .block:
            c.fill(r, night ? NSColor(hex: "#3a3a6a") : NSColor(hex: "#9c9c9c"))
            c.fill(CGRect(x: x, y: y + T - 1, width: T, height: 1), NSColor(white: 1, alpha: 0.3))
        case .pipe:
            c.fill(r, Pal.green)
            c.fill(CGRect(x: x + 1, y: y, width: 1, height: T), Pal.lgreen)
            c.fill(CGRect(x: x + T - 0.8, y: y, width: 0.8, height: T), NSColor(hex: "#1f6b22"))
        case .spike:
            c.cg.setFillColor((night ? Pal.magenta : NSColor(hex: "#dddddd")).cgColor)
            c.cg.move(to: CGPoint(x: x, y: y)); c.cg.addLine(to: CGPoint(x: x + T / 2, y: y + T - 0.5)); c.cg.addLine(to: CGPoint(x: x + T, y: y))
            c.cg.fillPath()
        case .platform:
            c.fill(CGRect(x: x, y: y + T - 2, width: T, height: 2), night ? Pal.cyan : NSColor(hex: "#f8d878"))
        case .empty: break
        }
    }

    /// Upside-down spike for ceilings.
    static func spikeDown(_ c: Canvas, x: CGFloat, y: CGFloat, color: NSColor) {
        let T = TileWorld.T
        c.cg.setFillColor(color.cgColor)
        c.cg.move(to: CGPoint(x: x, y: y + T)); c.cg.addLine(to: CGPoint(x: x + T / 2, y: y + 0.5)); c.cg.addLine(to: CGPoint(x: x + T, y: y + T))
        c.cg.fillPath()
    }
}
