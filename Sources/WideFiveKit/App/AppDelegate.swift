import AppKit
import ServiceManagement

public final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ConfigStore()
    var controller: StripController!
    var presenter: TouchBarPresenter?
    var statusItem: NSStatusItem!
    var previewWindow: NSWindow?
    public var openPreviewOnLaunch = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        controller = StripController(config: store.config)
        store.onChange = { [weak self] cfg in
            guard let self else { return }
            self.controller.apply(config: cfg)
            self.presenter?.hideControlStrip = cfg.hideControlStrip
            self.presenter?.replaceEscKey = cfg.replaceEscKey
            if let e = self.store.lastError { self.controller.toast("⚠️ \(e)") } else { self.controller.toast("✓ config reloaded") }
            self.rebuildMenu()
        }
        store.watch()

        let view = StripView(controller: controller, width: CGFloat(store.config.stripWidth ?? 1085))
        let p = TouchBarPresenter(stripView: view)
        p.hideControlStrip = store.config.hideControlStrip
        p.replaceEscKey = store.config.replaceEscKey
        presenter = p
        p.present()

        controller.onModeChange = { [weak self] _ in self?.rebuildMenu() }
        setupStatusItem()
        observeFrontmostApp()
        registerHotKeys()
        if let e = store.lastError { controller.toast("⚠️ \(e)") }
        if openPreviewOnLaunch || !TouchBarPresenter.isSupported { showPreview() }
    }

    public func applicationWillTerminate(_ notification: Notification) { presenter?.dismiss() }

    // MARK: Frontmost app → per-app layouts

    private func observeFrontmostApp() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostChanged(app)
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        controller.frontmostChanged(bundleId: app.bundleIdentifier, name: app.localizedName)
        guard let presenter else { return }
        if store.config.layout(for: app.bundleIdentifier)?.passthrough == true {
            presenter.minimize()
        } else if !presenter.isPresented {
            presenter.present()
        }
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        HotKeys.shared.register("ctrl+alt+cmd+space") { [weak self] in self?.controller.switchTo("launcher") }
        HotKeys.shared.register("ctrl+alt+cmd+h") { [weak self] in self?.controller.switchTo("home") }
        HotKeys.shared.register("ctrl+alt+cmd+g") { [weak self] in self?.controller.switchTo("plumber") }
        HotKeys.shared.register("ctrl+alt+cmd+p") { [weak self] in self?.togglePreview() }
        HotKeys.shared.register("ctrl+alt+cmd+t") { [weak self] in self?.presenter?.present() }
    }

    // MARK: Status menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "widefive")
        rebuildMenu()
    }

    private func item(_ title: String, _ action: Selector, key: String = "", state: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = state ? .on : .off
        return i
    }

    func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let header = NSMenuItem(title: "widefive — \(controller.current.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for m in controller.registry.modes {
            let i = item(m.title, #selector(pickMode(_:)), state: m.id == controller.current.id)
            i.representedObject = m.id
            i.image = NSImage(systemSymbolName: m.icon, accessibilityDescription: nil)
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Touch Bar Preview Window", #selector(togglePreview), key: "p"))
        menu.addItem(item("Re-take Touch Bar", #selector(retake)))
        menu.addItem(item("Hide Control Strip", #selector(toggleControlStrip), state: store.config.hideControlStrip))
        let themes = NSMenu()
        for t in Theme.all {
            let i = item(t.name.capitalized, #selector(pickTheme(_:)), state: t.name == store.config.theme)
            i.representedObject = t.name
            themes.addItem(i)
        }
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.addItem(themeItem)
        menu.addItem(.separator())
        menu.addItem(item("Edit Config…", #selector(editConfig), key: ","))
        menu.addItem(item("Reveal Config Folder", #selector(revealConfig)))
        menu.addItem(item("Reset Config to Defaults", #selector(resetConfig)))
        menu.addItem(item("Grant Accessibility (for key shortcuts)…", #selector(grantAX), state: Keys.ensureAccessibility(prompt: false)))
        if #available(macOS 13.0, *) {
            menu.addItem(item("Launch at Login", #selector(toggleLogin), state: SMAppService.mainApp.status == .enabled))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit widefive", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    @objc private func pickMode(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { controller.switchTo(id) } }
    @objc private func retake() { presenter?.present() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func grantAX() { Keys.ensureAccessibility(prompt: true) }
    @objc private func editConfig() { NSWorkspace.shared.open(ConfigStore.file) }
    @objc private func revealConfig() { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.file]) }
    @objc private func resetConfig() { store.resetToDefaults() }

    private func mutateConfig(_ f: (inout Config) -> Void) {
        var c = store.config
        f(&c)
        if let data = try? c.encoded() { try? data.write(to: ConfigStore.file) }
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        mutateConfig { $0.theme = name }
    }

    @objc private func toggleControlStrip() {
        mutateConfig { $0.hideControlStrip.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presenter?.present() }
    }

    @objc private func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch { controller.toast("Login item: \(error.localizedDescription)") }
            rebuildMenu()
        }
    }

    // MARK: Preview window (works on any Mac, with or without a Touch Bar)

    @objc func togglePreview() {
        if let w = previewWindow, w.isVisible { w.orderOut(nil) } else { showPreview() }
    }

    func showPreview() {
        if previewWindow == nil {
            let scale: CGFloat = 1.2
            let size = NSSize(width: 1085 * scale, height: 30 * scale)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "widefive — Touch Bar preview  (click = touch · arrows/space = game controls · esc = back)"
            w.contentAspectRatio = size
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            let v = StripView(controller: controller)
            w.contentView = v
            w.center()
            w.setFrameOrigin(NSPoint(x: w.frame.minX, y: 80))
            previewWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        previewWindow?.makeKeyAndOrderFront(nil)
        previewWindow?.makeFirstResponder(previewWindow?.contentView)
    }
}
