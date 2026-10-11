import AppKit

/// Input for two-player games. Player 0 = WASD + F/G (left half of the bar), player 1 = arrows + / . (right half).
/// Buttons: "L" "R" "U" "D" "F" (fire/nitro) "S" (special). Touch pads hide while the keyboard is locked.
public final class DuoInput {
    public var held: [Set<String>] = [[], []]
    private var edges: [Set<String>] = [[], []]
    public private(set) var usedKeyboard = false
    public var layout: [String] = ["L", "R", "U", "F", "S"]
    public var width: CGFloat = 1004
    /// How many touch pads to show (1 when playing a bot).
    public var players = 2
    private var owners: [Int: (Int, String)] = [:]
    private let btn: CGFloat = 30

    public init() {}

    public var visible: Bool { !KeyCapture.shared.active }

    public func isDown(_ p: Int, _ b: String) -> Bool { held[p].contains(b) }
    public func take(_ p: Int, _ b: String) -> Bool { edges[p].remove(b) != nil }
    public func clearEdges() { edges = [[], []] }
    public func reset() { held = [[], []]; edges = [[], []]; owners = [:] }

    private func set(_ p: Int, _ b: String, _ down: Bool) {
        if down { if !held[p].contains(b) { edges[p].insert(b) }; held[p].insert(b) } else { held[p].remove(b) }
    }

    public func key(_ k: GameKey, down: Bool) {
        usedKeyboard = true
        let map: (Int, String)?
        switch k {
        case .p1Left: map = (0, "L"); case .p1Right: map = (0, "R"); case .p1Up: map = (0, "U"); case .p1Down: map = (0, "D")
        case .p1Fire, .jump: map = (0, "F"); case .p1Special: map = (0, "S")
        case .left: map = (1, "L"); case .right: map = (1, "R"); case .up: map = (1, "U"); case .down: map = (1, "D")
        case .p2Fire, .action: map = (1, "F"); case .p2Special, .run: map = (1, "S")
        }
        if let (p, b) = map { set(p, b, down) }
    }

    public func rects(_ p: Int) -> [(String, CGRect)] {
        let n = CGFloat(layout.count)
        let x0 = p == 0 ? StripController.gameChromeWidth + 2 : width - n * (btn + 2)
        return layout.enumerated().map { ($0.element, CGRect(x: x0 + CGFloat($0.offset) * (btn + 2), y: 1, width: btn, height: 28)) }
    }

    private func hit(_ x: CGFloat) -> (Int, String)? {
        guard visible else { return nil }
        for p in 0..<players { if let r = rects(p).first(where: { $0.1.minX <= x && x <= $0.1.maxX }) { return (p, r.0) } }
        return nil
    }

    @discardableResult public func began(_ t: StripTouch) -> Bool {
        guard let h = hit(t.x) else { return false }
        owners[t.id] = h; set(h.0, h.1, true); return true
    }
    public func moved(_ t: StripTouch) {
        guard let cur = owners[t.id], let h = hit(t.x), h != cur, h.0 == cur.0 else { return }
        set(cur.0, cur.1, false); owners[t.id] = h; set(h.0, h.1, true)
    }
    public func ended(_ t: StripTouch) {
        guard let cur = owners.removeValue(forKey: t.id) else { return }
        if !owners.values.contains(where: { $0 == cur }) { set(cur.0, cur.1, false) }
    }

    func draw(_ c: Canvas, colors: [NSColor] = [Pal.cyan, Pal.magenta]) {
        guard visible else { return }
        let labels = ["L": "◀", "R": "▶", "U": "▲", "D": "▼", "F": "●", "S": "★"]
        for p in 0..<players {
            for (b, r) in rects(p) {
                let on = held[p].contains(b)
                c.roundRect(r, radius: 6, fill: colors[p].withAlphaComponent(on ? 0.7 : 0.22), stroke: NSColor(white: 1, alpha: 0.3), lineWidth: 0.6)
                c.text(labels[b] ?? b, x: r.midX, size: 11, color: .white, weight: .heavy, align: .center)
            }
        }
    }
}

/// Modes that can jump straight into gameplay for `--snapshot <mode>:demo`.
public protocol DemoStartable: AnyObject { func startDemo() }
