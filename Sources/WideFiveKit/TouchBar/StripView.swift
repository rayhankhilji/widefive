import AppKit

/// The single view hosted in the Touch Bar (and in the preview window). Converts NSTouch / mouse events into StripTouch.
public final class StripView: NSView {
    public let controller: StripController
    public var preferredWidth: CGFloat = 1085
    private var touchIds: [ObjectIdentifier: Int] = [:]
    private var touchStarts: [Int: (x: CGFloat, t: Double)] = [:]
    private var nextId = 1
    private let mouseId = -1

    public init(controller: StripController, width: CGFloat = 1085) {
        self.controller = controller
        self.preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        allowedTouchTypes = [.direct]
        wantsRestingTouches = true
        wantsLayer = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.attach(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize { NSSize(width: preferredWidth, height: 30) }
    public override var isFlipped: Bool { false }
    public override var acceptsFirstResponder: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        // The preview window scales the 30pt-tall strip up; draw in strip coordinates.
        let scale = bounds.height / 30
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        controller.render(cg, size: CGSize(width: bounds.width / scale, height: 30))
        cg.restoreGState()
    }

    private func stripPoint(_ p: NSPoint) -> CGPoint {
        let scale = bounds.height / 30
        return CGPoint(x: p.x / scale, y: p.y / scale)
    }

    private func makeTouch(id: Int, at p: CGPoint) -> StripTouch {
        let now = CACurrentMediaTime()
        let start = touchStarts[id] ?? (p.x, now)
        return StripTouch(id: id, x: p.x, y: p.y, startX: start.x, startTime: start.t, time: now)
    }

    // MARK: Touch Bar touches

    public override func touchesBegan(with event: NSEvent) {
        for t in event.touches(matching: .began, in: self) {
            let id = nextId; nextId += 1
            touchIds[ObjectIdentifier(t.identity as AnyObject)] = id
            let p = stripPoint(t.location(in: self))
            touchStarts[id] = (p.x, CACurrentMediaTime())
            controller.touchBegan(makeTouch(id: id, at: p))
        }
    }

    public override func touchesMoved(with event: NSEvent) {
        for t in event.touches(matching: .moved, in: self) {
            guard let id = touchIds[ObjectIdentifier(t.identity as AnyObject)] else { continue }
            controller.touchMoved(makeTouch(id: id, at: stripPoint(t.location(in: self))))
        }
    }

    public override func touchesEnded(with event: NSEvent) { finish(event.touches(matching: .ended, in: self)) }
    public override func touchesCancelled(with event: NSEvent) { finish(event.touches(matching: .cancelled, in: self)) }

    private func finish(_ set: Set<NSTouch>) {
        for t in set {
            let key = ObjectIdentifier(t.identity as AnyObject)
            guard let id = touchIds.removeValue(forKey: key) else { continue }
            controller.touchEnded(makeTouch(id: id, at: stripPoint(t.location(in: self))))
            touchStarts[id] = nil
        }
    }

    // MARK: Mouse (preview window)

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = stripPoint(convert(event.locationInWindow, from: nil))
        touchStarts[mouseId] = (p.x, CACurrentMediaTime())
        controller.touchBegan(makeTouch(id: mouseId, at: p))
    }

    public override func mouseDragged(with event: NSEvent) {
        controller.touchMoved(makeTouch(id: mouseId, at: stripPoint(convert(event.locationInWindow, from: nil))))
    }

    public override func mouseUp(with event: NSEvent) {
        controller.touchEnded(makeTouch(id: mouseId, at: stripPoint(convert(event.locationInWindow, from: nil))))
        touchStarts[mouseId] = nil
    }

    // MARK: Keyboard (preview window)

    private static func gameKey(_ e: NSEvent) -> GameKey? {
        switch e.keyCode {
        case 123: return .left
        case 124: return .right
        case 126: return .up
        case 125: return .down
        case 49: return .jump        // space
        case 6, 7: return .run       // z / x
        case 36: return .action      // return
        default:
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "a": return .left
            case "d": return .right
            case "w": return .jump
            case "s": return .down
            default: return nil
            }
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.goBack(); return } // esc
        if let k = Self.gameKey(event) { if !event.isARepeat { controller.keyDown(k) } } else { super.keyDown(with: event) }
    }

    public override func keyUp(with event: NSEvent) {
        if let k = Self.gameKey(event) { controller.keyUp(k) } else { super.keyUp(with: event) }
    }
}
