import AppKit

enum Pal {
    static let red = NSColor(hex: "#e52521"), skin = NSColor(hex: "#f8b878"), hair = NSColor(hex: "#6b3e1e")
    static let blue = NSColor(hex: "#2038ec"), yellow = NSColor(hex: "#fbd000"), white = NSColor.white, black = NSColor.black
    static let brown = NSColor(hex: "#a0522d"), dark = NSColor(hex: "#3b1f0e"), green = NSColor(hex: "#43b047"), lgreen = NSColor(hex: "#8ce68c")
    static let sky = NSColor(hex: "#5c94fc"), orange = NSColor(hex: "#f87c00"), grey = NSColor(hex: "#8c8c8c"), pink = NSColor(hex: "#ff8ad8")
    static let cyan = NSColor(hex: "#21e6ff"), magenta = NSColor(hex: "#ff2bd6"), purple = NSColor(hex: "#7b2cff")
}

enum Sprites {
    static let hero: [Character: NSColor] = ["R": Pal.red, "S": Pal.skin, "H": Pal.hair, "B": Pal.blue, "Y": Pal.yellow, "K": Pal.black,
                                             "r": NSColor(hex: "#a3161a"), "b": NSColor(hex: "#14249a")]

    static let smallStand = Sprite([
        "..RRRR.",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "..BRRB.",
        ".BbYbB.",
        ".HH.HH.",
    ], hero)
    static let smallRun = Sprite([
        "..RRRR.",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "S.BRRB.",
        ".BbYbBS",
        "HH...HH",
    ], hero)
    static let smallJump = Sprite([
        "..RRRRS",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "SBBRRB.",
        ".BbYbB.",
        "HH..HH.",
    ], hero)
    static let bigStand = Sprite([
        "..RRRR.",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        ".RRBRR.",
        "rRRBRRr",
        "S.BYB.S",
        ".BB.BB.",
        ".HH.HH.",
    ], hero)
    static let bigRun = Sprite([
        "..RRRR.",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        ".RRBRRS",
        "SrRBRr.",
        "..BYB..",
        ".BB.BB.",
        "HH...HH",
    ], hero)
    static let bigJump = Sprite([
        "..RRRRS",
        ".RRRRrr",
        ".HHSKS.",
        ".HSSSSS",
        "..SSSS.",
        "SrRBRr.",
        ".RRBRR.",
        "..BYB..",
        "BB..BB.",
        "H....H.",
    ], hero)

    static let smallDie = Sprite([
        "S.RRR.S",
        "SRRRRrS",
        ".SKSKS.",
        ".SSSSS.",
        "..BRB..",
        ".BbYbB.",
        ".HH.HH.",
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
            if night {
                c.gradient(r, [NSColor(hex: "#2a1b4a"), NSColor(hex: "#150c2a")])
                c.fill(CGRect(x: x, y: y + T - 0.8, width: T, height: 0.8), Pal.purple)
                c.fill(CGRect(x: x, y: y + T - 0.3, width: T, height: 0.3), NSColor(hex: "#c79bff"))
            } else {
                c.gradient(r, [NSColor(hex: "#c46a2c"), NSColor(hex: "#7a3a12")])
                c.fill(CGRect(x: x, y: y + T - 1.6, width: T, height: 1.6), NSColor(hex: "#43b047"))
                c.fill(CGRect(x: x, y: y + T - 0.5, width: T, height: 0.5), NSColor(hex: "#8ce68c"))
                c.fill(CGRect(x: x + 1 + CGFloat(Int(x) % 3), y: y + T - 2.2, width: 0.8, height: 0.6), NSColor(hex: "#43b047"))
            }
            let k = abs(Int(x * 7 + y * 3)) % 5
            c.fill(CGRect(x: x + CGFloat(k) * 0.8 + 0.4, y: y + 1 + CGFloat(k % 2), width: 0.7, height: 0.7), NSColor(white: 0, alpha: 0.22))
        case .brick:
            c.gradient(r, [NSColor(hex: "#d4733a"), NSColor(hex: "#9a4a16")])
            c.fill(CGRect(x: x, y: y + 2.2, width: T, height: 0.5), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x, y: y, width: T, height: 0.4), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x + 2.3, y: y + 2.7, width: 0.5, height: 2.3), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x + 0.2, y: y + 0.4, width: 0.5, height: 1.8), NSColor(hex: "#5a2a0a"))
            c.fill(CGRect(x: x, y: y + T - 0.5, width: T, height: 0.5), NSColor(hex: "#f0a070"))
            c.fill(CGRect(x: x + 3, y: y + 2.7, width: 1.5, height: 0.4), NSColor(white: 1, alpha: 0.2))
        case .question:
            let glow = 0.8 + 0.2 * sin(time * 5)
            c.roundRect(r.insetBy(dx: 0.1, dy: 0.1), radius: 0.8, fill: NSColor(hex: "#f8b800").blended(withFraction: CGFloat(1 - glow), of: NSColor(hex: "#c06800"))!)
            c.fill(CGRect(x: x + 0.4, y: y + T - 0.9, width: T - 0.8, height: 0.5), NSColor(hex: "#ffe27a"))
            c.fill(CGRect(x: x + 0.4, y: y + 0.4, width: T - 0.8, height: 0.5), NSColor(hex: "#a05000"))
            for (dx, dy) in [(0.9, 0.9), (T - 1.5, 0.9), (0.9, T - 1.7), (T - 1.5, T - 1.7)] as [(CGFloat, CGFloat)] {
                c.fill(CGRect(x: x + dx, y: y + dy, width: 0.6, height: 0.6), NSColor(hex: "#7a3a00"))
            }
            let bob = CGFloat(sin(time * 4)) * 0.25
            c.text("?", x: x + T / 2 + 0.3, y: y + 0.2 + bob, size: 4.6, color: NSColor(hex: "#7a3a00"), weight: .black, align: .center)
            c.text("?", x: x + T / 2, y: y + 0.5 + bob, size: 4.6, color: .white, weight: .black, align: .center)
        case .used:
            c.roundRect(r.insetBy(dx: 0.1, dy: 0.1), radius: 0.8, fill: NSColor(hex: "#8a5a2a"))
            c.fill(r.insetBy(dx: 1.2, dy: 1.2), NSColor(hex: "#6a4220"))
            c.fill(CGRect(x: x + 0.4, y: y + T - 0.8, width: T - 0.8, height: 0.4), NSColor(hex: "#b07a44"))
        case .block:
            c.gradient(r, night ? [NSColor(hex: "#4a4a86"), NSColor(hex: "#2a2a56")] : [NSColor(hex: "#bdbdbd"), NSColor(hex: "#7c7c7c")])
            c.fill(CGRect(x: x, y: y + T - 0.7, width: T, height: 0.7), NSColor(white: 1, alpha: 0.4))
            c.fill(CGRect(x: x + T - 0.6, y: y, width: 0.6, height: T), NSColor(white: 0, alpha: 0.25))
            c.fill(CGRect(x: x, y: y, width: T, height: 0.5), NSColor(white: 0, alpha: 0.3))
        case .pipe:
            c.gradient(r, [NSColor(hex: "#1f6b22"), Pal.lgreen, Pal.green, NSColor(hex: "#1f6b22")], horizontal: true)
            c.fill(CGRect(x: x + 1.2, y: y, width: 0.6, height: T), NSColor(white: 1, alpha: 0.45))
        case .spike:
            if night { Glow.radial(c, CGPoint(x: x + T / 2, y: y + 1.5), 4, Pal.magenta, alpha: 0.35) }
            c.cg.setFillColor((night ? Pal.magenta : NSColor(hex: "#dddddd")).cgColor)
            c.cg.move(to: CGPoint(x: x, y: y)); c.cg.addLine(to: CGPoint(x: x + T / 2, y: y + T - 0.5)); c.cg.addLine(to: CGPoint(x: x + T, y: y))
            c.cg.fillPath()
            c.cg.setFillColor(NSColor(white: 1, alpha: 0.45).cgColor)
            c.cg.move(to: CGPoint(x: x + T / 2, y: y + T - 0.5)); c.cg.addLine(to: CGPoint(x: x + T / 2, y: y)); c.cg.addLine(to: CGPoint(x: x + 0.8, y: y))
            c.cg.fillPath()
        case .platform:
            let pr = CGRect(x: x, y: y + T - 2, width: T, height: 2)
            if night { Glow.radial(c, CGPoint(x: pr.midX, y: pr.midY), 4, Pal.cyan, alpha: 0.3) }
            c.fill(pr, night ? NSColor(hex: "#0e6f86") : NSColor(hex: "#d0a848"))
            c.fill(CGRect(x: x, y: pr.maxY - 0.6, width: T, height: 0.6), night ? Pal.cyan : NSColor(hex: "#f8e8a8"))
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
