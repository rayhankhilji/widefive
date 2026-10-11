import AppKit

/// Takes over the whole Touch Bar using the private system-modal APIs (same technique as MTMR / Pock).
/// Nothing is patched on disk: quitting widefive restores the stock Touch Bar.
public final class TouchBarPresenter: NSObject, NSTouchBarDelegate {
    public static let mainID = NSTouchBarItem.Identifier("com.widefive.strip")
    public static let escID = NSTouchBarItem.Identifier("com.widefive.esc")
    public static let trayID = NSTouchBarItem.Identifier("com.widefive.tray")

    public let touchBar = NSTouchBar()
    public let stripView: StripView
    private var trayItem: NSCustomTouchBarItem?
    public var hideControlStrip = true
    public private(set) var isPresented = false
    /// Human-readable result of the last present() call, shown in the menu and logged.
    public private(set) var status = "not presented yet"
    public var onStatusChange: (() -> Void)?

    public init(stripView: StripView) {
        self.stripView = stripView
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.mainID]
    }

    public var replaceEscKey = false {
        didSet { touchBar.escapeKeyReplacementItemIdentifier = replaceEscKey ? Self.escID : nil }
    }

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case Self.mainID: item.view = stripView
        case Self.escID:
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 30))
            v.widthAnchor.constraint(equalToConstant: 1).isActive = true
            item.view = v
        default: return nil
        }
        return item
    }

    // MARK: Private API plumbing

    private typealias ClassVoidObj = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias PresentWithTray = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
    private typealias PresentWithPlacement = @convention(c) (AnyObject, Selector, AnyObject, Int64, AnyObject?) -> Void
    private typealias DFRSetPresence = @convention(c) (CFString, Bool) -> Void
    private typealias DFRShowsCloseBox = @convention(c) (Bool) -> Void

    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private static func classIMP<T>(_ cls: AnyClass, _ name: String, as: T.Type) -> (T, Selector)? {
        let sel = NSSelectorFromString(name)
        guard let m = class_getClassMethod(cls, sel) else { return nil }
        return (unsafeBitCast(method_getImplementation(m), to: T.self), sel)
    }

    public static var isSupported: Bool {
        classIMP(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:", as: PresentWithTray.self) != nil
            || classIMP(NSTouchBar.self, "presentSystemModalFunctionBar:systemTrayItemIdentifier:", as: PresentWithTray.self) != nil
    }

    private func installTrayItem() {
        guard trayItem == nil else { return }
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        let button = NSButton(title: "", target: self, action: #selector(trayTapped))
        button.image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "widefive")
        button.bezelColor = NSColor(hex: "#ff2bd6")
        item.view = button
        trayItem = item
        if let (f, sel) = Self.classIMP(NSTouchBarItem.self, "addSystemTrayItem:", as: ClassVoidObj.self) {
            f(NSTouchBarItem.self, sel, item)
        } else { NSLog("widefive: addSystemTrayItem: unavailable") }
        if let h = Self.dfr, let s = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") {
            unsafeBitCast(s, to: DFRSetPresence.self)(Self.trayID.rawValue as CFString, true)
        }
    }

    @objc private func trayTapped() { present() }

    public func present() {
        installTrayItem()
        if let h = Self.dfr, let s = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") {
            unsafeBitCast(s, to: DFRShowsCloseBox.self)(false)
        }
        let tray = Self.trayID.rawValue as NSString
        var method = ""
        if hideControlStrip,
           let (f, sel) = Self.classIMP(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:", as: PresentWithPlacement.self) {
            f(NSTouchBar.self, sel, touchBar, 1, tray)
            method = "placement"
        } else if let (f, sel) = Self.classIMP(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:", as: PresentWithTray.self) {
            f(NSTouchBar.self, sel, touchBar, tray)
            method = "touchbar"
        } else if let (f, sel) = Self.classIMP(NSTouchBar.self, "presentSystemModalFunctionBar:systemTrayItemIdentifier:", as: PresentWithTray.self) {
            f(NSTouchBar.self, sel, touchBar, tray)
            method = "functionbar"
        } else {
            status = "system-modal API missing on this macOS"
            NSLog("widefive: %@", status)
            return
        }
        isPresented = true
        status = "presented (\(method)), checking…"
        NSLog("widefive: present via %@ (DFRFoundation %@, strip %.0fpt)", method, Self.dfr == nil ? "NOT loaded" : "loaded", stripView.preferredWidth)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.verify(method) }
    }

    /// The strip view only gets a window once the Touch Bar server actually hosts it.
    private func verify(_ method: String) {
        guard isPresented else { return }
        if let w = stripView.window, stripView.bounds.height > 0 {
            status = "showing (\(method), \(Int(stripView.bounds.width))pt)"
            NSLog("widefive: strip hosted in %@ frame=%@", String(describing: type(of: w)), NSStringFromRect(stripView.frame))
        } else {
            let size = stripView.window == nil ? "no window" : "\(Int(stripView.bounds.width))×\(Int(stripView.bounds.height))pt"
            status = "not showing (\(method), \(size))"
            NSLog("widefive: %@", status)
        }
        onStatusChange?()
    }

    /// Temporarily hand the Touch Bar back to the frontmost app.
    public func minimize() {
        for name in ["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"] {
            if let (f, sel) = Self.classIMP(NSTouchBar.self, name, as: ClassVoidObj.self) { f(NSTouchBar.self, sel, touchBar); break }
        }
        isPresented = false
    }

    public func dismiss() {
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            if let (f, sel) = Self.classIMP(NSTouchBar.self, name, as: ClassVoidObj.self) { f(NSTouchBar.self, sel, touchBar); break }
        }
        isPresented = false
    }
}
