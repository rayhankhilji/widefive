import AppKit

public struct StripTouch {
    public let id: Int
    public var x: CGFloat
    public var y: CGFloat
    public let startX: CGFloat
    public let startTime: Double
    public var time: Double
    public var dx: CGFloat { x - startX }
    public var duration: Double { time - startTime }
}

/// Everything a mode can do to the outside world.
public final class ModeContext {
    public var size: CGSize = CGSize(width: 1085, height: 30)
    public var theme: Theme = .neon
    public var config: Config = .default
    public var requestRedraw: () -> Void = {}
    public var switchMode: (String) -> Void = { _ in }
    public var goBack: () -> Void = {}
    public var toast: (String) -> Void = { _ in }
    public var run: (Action) -> Void = { _ in }
    public var frontmostBundleId: String?
    public var frontmostAppName: String?
    public init() {}
}

public protocol StripMode: AnyObject {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    /// true → redraw at 60fps; false → redraw every `refreshInterval`.
    var isAnimated: Bool { get }
    var refreshInterval: Double { get }
    /// Whether global gestures (2-finger volume etc.) are active while this mode is shown.
    var allowsGestures: Bool { get }
    /// Shows the small exit button at the far left (games, fullscreen modes).
    var showsExitButton: Bool { get }
    /// Games get the key-lock button, P-to-pause and keyboard capture.
    var isGame: Bool { get }
    /// Two-player games get separate WASD / arrow keys instead of collapsed ones.
    var isTwoPlayer: Bool { get }

    func activate(_ ctx: ModeContext)
    func deactivate()
    func update(dt: Double)
    func draw(_ c: Canvas)
    func touchBegan(_ t: StripTouch)
    func touchMoved(_ t: StripTouch)
    func touchEnded(_ t: StripTouch)
    func touchCancelled(_ t: StripTouch)
    func keyDown(_ key: GameKey)
    func keyUp(_ key: GameKey)
}

public enum GameKey {
    case left, right, up, down, jump, run, action
    /// Player-1 keys (WASD + F/G). Arrows and / . are player 2 in two-player games.
    case p1Left, p1Right, p1Up, p1Down, p1Fire, p1Special, p2Fire, p2Special

    /// Single-player games see WASD as arrows.
    public var collapsed: GameKey {
        switch self {
        case .p1Left: return .left
        case .p1Right: return .right
        case .p1Up: return .up
        case .p1Down: return .down
        case .p1Fire, .p2Fire: return .run
        case .p1Special, .p2Special: return .action
        default: return self
        }
    }
}

public extension StripMode {
    var isAnimated: Bool { false }
    var refreshInterval: Double { 1.0 }
    var allowsGestures: Bool { true }
    var showsExitButton: Bool { false }
    var isGame: Bool { false }
    var isTwoPlayer: Bool { false }
    func deactivate() {}
    func update(dt: Double) {}
    func touchBegan(_ t: StripTouch) {}
    func touchMoved(_ t: StripTouch) {}
    func touchEnded(_ t: StripTouch) {}
    func touchCancelled(_ t: StripTouch) { touchEnded(t) }
    func keyDown(_ key: GameKey) {}
    func keyUp(_ key: GameKey) {}
}

public final class ModeRegistry {
    public private(set) var modes: [StripMode] = []
    public init() {}
    public func register(_ m: StripMode) { modes.removeAll { $0.id == m.id }; modes.append(m) }
    public func mode(_ id: String) -> StripMode? { modes.first { $0.id == id } }

    public static func standard() -> ModeRegistry {
        let r = ModeRegistry()
        r.register(HomeMode())
        r.register(LauncherMode(registry: r))
        r.register(PlumberGame())
        r.register(DashGame())
        r.register(FlipGame())
        r.register(SnakeGame())
        r.register(PongGame())
        r.register(BreakoutGame())
        r.register(FlappyGame())
        r.register(ShooterGame())
        r.register(RaceGame())
        r.register(DuelGame())
        r.register(ControlMode())
        for k in ["brightness", "keyboard", "volume"] { r.register(AdjustMode(k)) }
        r.register(PianoMode())
        r.register(VisualizerMode())
        r.register(AmbientMode())
        r.register(ClipboardMode())
        r.register(DockMode())
        r.register(StatsMode())
        r.register(TimerMode())
        r.register(CalculatorMode())
        r.register(EmojiMode())
        r.register(PetMode())
        return r
    }
}

extension PlumberGame { public var isGame: Bool { true } }
extension DashGame { public var isGame: Bool { true } }
extension FlipGame { public var isGame: Bool { true } }
extension SnakeGame { public var isGame: Bool { true } }
extension PongGame { public var isGame: Bool { true } }
extension BreakoutGame { public var isGame: Bool { true } }
extension FlappyGame { public var isGame: Bool { true } }
extension ShooterGame { public var isGame: Bool { true } }
