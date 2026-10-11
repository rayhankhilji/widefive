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
    private let btn: CGFloat = 25
    private let gap: CGFloat = 2
    private let groupGap: CGFloat = 5

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

    /// Compact pill buttons: movement group, a small gap, then the action group. P1 hugs the left chrome, P2 the right edge.
    public func rects(_ p: Int) -> [(String, CGRect)] {
        let moves = layout.filter { ["L", "R", "U", "D"].contains($0) }.count
        let total = CGFloat(layout.count) * (btn + gap) - gap + (moves > 0 && moves < layout.count ? groupGap : 0)
        var x = p == 0 ? StripController.gameChromeWidth + 3 : width - total - 3
        return layout.enumerated().map { i, b in
            if i == moves, moves > 0 { x += groupGap }
            defer { x += btn + gap }
            return (b, CGRect(x: x, y: 4, width: btn, height: 22))
        }
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
        for p in 0..<players {
            let rs = rects(p)
            guard let first = rs.first?.1, let last = rs.last?.1 else { continue }
            let tint = colors.indices.contains(p) ? colors[p] : Pal.cyan
            let back = CGRect(x: first.minX - 2, y: first.minY - 2, width: last.maxX - first.minX + 4, height: first.height + 4)
            c.roundRect(back, radius: back.height / 2, fill: NSColor(white: 0, alpha: 0.28), stroke: tint.withAlphaComponent(0.18), lineWidth: 0.5)
            for (b, r) in rs { TouchButton.draw(c, r, glyph: b, on: held[p].contains(b), tint: tint) }
            let tag = p == 0 ? "P1" : "P2"
            let tx = p == 0 ? back.maxX + 2 : back.minX - 2
            c.text(tag, x: tx, y: back.midY - 2.5, size: 5, color: tint.withAlphaComponent(0.7), weight: .black, align: p == 0 ? .left : .right)
        }
    }
}

/// Modes that can jump straight into gameplay for `--snapshot <mode>:demo`.
public protocol DemoStartable: AnyObject { func startDemo() }
