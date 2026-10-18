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
            Hardware.shared.overrideWidth(cfg.stripWidth.map { CGFloat($0) })
            self.presenter?.stripView.setPreferredWidth(Hardware.shared.touchBarWidth)
            self.statusItem?.isVisible = !cfg.hideMenuBarIcon
            if let e = self.store.lastError { self.controller.toast("⚠️ \(e)") } else { self.controller.toast("✓ config reloaded") }
            self.rebuildMenu()
        }
        store.watch()

        Hardware.shared.overrideWidth(store.config.stripWidth.map { CGFloat($0) })
        let view = StripView(controller: controller, width: Hardware.shared.touchBarWidth)
        view.learnsWidth = store.config.stripWidth == nil
        let p = TouchBarPresenter(stripView: view)
        p.hideControlStrip = store.config.hideControlStrip
        p.replaceEscKey = store.config.replaceEscKey
        presenter = p
        p.onStatusChange = { [weak self] in self?.rebuildMenu() }
        p.present()
        // The Touch Bar server sometimes ignores a presentation made during launch; ask again once things settle.
        for delay in [0.6, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.represent() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.represent() }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.represent()
        }

        controller.onModeChange = { [weak self] _ in self?.rebuildMenu() }
        controller.onThemePicked = { [weak self] name in self?.mutateConfig { $0.theme = name } }
        setupKeyCapture()
        setupStatusItem()
        observeFrontmostApp()
        registerHotKeys()
        setupUpdater()
        setupAgents()
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
        } else {
            presenter.present()
        }
    }

    private func represent() {
        guard let presenter else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if store.config.layout(for: front)?.passthrough == true { return }
        presenter.present()
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        HotKeys.shared.register("ctrl+alt+cmd+space") { [weak self] in self?.controller.switchTo("launcher") }
        HotKeys.shared.register("ctrl+alt+cmd+h") { [weak self] in self?.controller.switchTo("home") }
        HotKeys.shared.register("ctrl+alt+cmd+g") { [weak self] in self?.controller.switchTo("plumber") }
        HotKeys.shared.register("ctrl+alt+cmd+p") { [weak self] in self?.togglePreview() }
        HotKeys.shared.register("ctrl+alt+cmd+t") { [weak self] in self?.presenter?.present() }
        HotKeys.shared.register("ctrl+alt+cmd+k") { [weak self] in self?.toggleKeyLock() }
        HotKeys.shared.register("ctrl+alt+cmd+c") { [weak self] in self?.controller.switchTo("control") }
        HotKeys.shared.register("ctrl+alt+cmd+m") { [weak self] in self?.peekMenu() }
    }

    // MARK: Game key lock

    private func setupKeyCapture() {
        let kc = KeyCapture.shared
        kc.onKey = { [weak self] key, down in down ? self?.controller.keyDown(key) : self?.controller.keyUp(key) }
        kc.onPause = { [weak self] in self?.controller.togglePause() }
        kc.onExit = { [weak self] in self?.controller.goBack() }
        kc.onChange = { [weak self] on in
            self?.controller.toast(on ? "🎮 keys locked to the bar — ⌃⌥⌘K or esc to release" : "⌨️ keys back to your Mac")
            self?.rebuildMenu()
        }
        controller.onToggleKeyLock = { [weak self] in self?.toggleKeyLock() }
    }

    @objc func toggleKeyLock() {
        if !KeyCapture.shared.active, !controller.current.isGame { controller.switchTo("plumber") }
        if !KeyCapture.shared.toggle(), !KeyCapture.shared.active {
            if !Keys.ensureAccessibility(prompt: false) { controller.toast("Grant Accessibility to widefive to lock keys") }
        }
    }

    /// Shows the menu-bar icon for 20s even when it's hidden, so you can still reach settings.
    private func peekMenu() {
        statusItem.isVisible = true
        statusItem.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            self.statusItem.isVisible = !self.store.config.hideMenuBarIcon
        }
    }

    // MARK: Coding agents

    private func setupAgents() {
        let m = AgentMonitor.shared
        m.config = store.config.agents
        m.onChange = { [weak self] in
            self?.controller.setNeedsDisplay()
            self?.rebuildMenu()
        }
        m.onAttention = { [weak self] a in
            guard let self else { return }
            let cfg = self.store.config.agents
            if cfg.toast {
                let verb = a.state == .done ? "✅ \(a.name) is done" : "🔔 \(a.name) needs you"
                self.controller.toast("\(verb)  ·  \(a.message ?? a.detail)")
            }
            if cfg.sound { NSSound(named: "Pop")?.play() }
        }
        m.start()
    }

    private func agentsMenu() -> NSMenu {
        let menu = NSMenu()
        let agents = AgentMonitor.shared.agents
        if agents.isEmpty {
            let none = NSMenuItem(title: AgentMonitor.shared.config.enabled ? "No coding agents running" : "Agent monitor is off", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for a in agents {
            let mark = a.state == .waiting ? "🔴 " : a.state == .done ? "✅ " : ""
            let i = item("\(mark)\(a.name) — \(a.detail)  (\(a.stateLabel))", #selector(pickAgent(_:)))
            i.representedObject = a.id
            i.image = NSImage(systemSymbolName: a.icon, accessibilityDescription: nil)
            i.toolTip = a.message
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Agents on the Bar", #selector(showAgentsMode)))
        menu.addItem(.separator())
        for kind in AgentHooks.Kind.allCases {
            let installed = AgentHooks.isInstalled(kind)
            let i = item("\(installed ? "Remove" : "Install") \(kind.title) Hooks (exact “needs you” alerts)", #selector(toggleHook(_:)), state: installed)
            i.representedObject = kind.rawValue
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("Monitor Coding Agents", #selector(toggleAgentsEnabled), state: store.config.agents.enabled))
        menu.addItem(item("Toast When an Agent Needs You", #selector(toggleAgentToast), state: store.config.agents.toast))
        menu.addItem(item("Play a Sound Too", #selector(toggleAgentSound), state: store.config.agents.sound))
        menu.addItem(item("Look Through Browser Tabs", #selector(toggleAgentBrowsers), state: store.config.agents.scanBrowsers))
        return menu
    }

    @objc private func pickAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let a = AgentMonitor.shared.agents.first(where: { $0.id == id }) else { return }
        AgentMonitor.shared.focus(a)
    }
    @objc private func showAgentsMode() { controller.switchTo("agents") }
    @objc private func toggleHook(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = AgentHooks.Kind(rawValue: raw) else { return }
        let note = AgentHooks.isInstalled(kind) ? AgentHooks.uninstall(kind) : AgentHooks.install(kind)
        controller.toast(note)
        rebuildMenu()
    }
    @objc private func toggleAgentsEnabled() { mutateConfig { $0.agents.enabled.toggle() } }
    @objc private func toggleAgentToast() { mutateConfig { $0.agents.toast.toggle() } }
    @objc private func toggleAgentSound() { mutateConfig { $0.agents.sound.toggle() } }
    @objc private func toggleAgentBrowsers() { mutateConfig { $0.agents.scanBrowsers.toggle() } }

    // MARK: Updates

    private func setupUpdater() {
        Updater.shared.onUpdateFound = { [weak self] version in
            self?.controller.toast("⬆ widefive \(version) is ready — menu → Install Update")
            self?.rebuildMenu()
        }
        Updater.shared.start()
        rebuildMenu()
    }

    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc private func toggleAutoUpdateChecks() {
        Updater.shared.automaticallyChecks.toggle()
        rebuildMenu()
    }

    private func addUpdateItems(to menu: NSMenu) {
        let updater = Updater.shared
        guard updater.isEnabled else {
            let off = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
            off.toolTip = "Auto-update is off: \(updater.disabledReason ?? "unavailable")"
            off.isEnabled = false
            menu.addItem(off)
            return
        }
        let title = updater.pendingVersion.map { "Install Update \($0)…" } ?? "Check for Updates…"
        let check = item(title, #selector(checkForUpdates))
        check.image = updater.pendingVersion == nil ? nil : NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        menu.addItem(check)
        menu.addItem(item("Automatically Check for Updates", #selector(toggleAutoUpdateChecks), state: updater.automaticallyChecks))
    }

    // MARK: Status menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "widefive")
        statusItem.isVisible = !store.config.hideMenuBarIcon
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
        let header = NSMenuItem(title: "widefive \(Updater.versionDescription) — \(controller.current.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let hw = NSMenuItem(title: Hardware.shared.summary, action: nil, keyEquivalent: "")
        hw.isEnabled = false
        menu.addItem(hw)
        let tb = NSMenuItem(title: "Touch Bar: \(presenter?.status ?? "—")", action: nil, keyEquivalent: "")
        tb.isEnabled = false
        menu.addItem(tb)
        menu.addItem(.separator())
        for m in controller.registry.modes {
            let i = item(m.title, #selector(pickMode(_:)), state: m.id == controller.current.id)
            i.representedObject = m.id
            i.image = NSImage(systemSymbolName: m.icon, accessibilityDescription: nil)
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let waiting = AgentMonitor.shared.waiting.count
        let agentsItem = NSMenuItem(title: waiting > 0 ? "Coding Agents — \(waiting) need\(waiting == 1 ? "s" : "") you" : "Coding Agents", action: nil, keyEquivalent: "")
        agentsItem.image = NSImage(systemSymbolName: waiting > 0 ? "bell.badge.fill" : "person.2.wave.2", accessibilityDescription: nil)
        agentsItem.submenu = agentsMenu()
        menu.addItem(agentsItem)
        menu.addItem(.separator())
        menu.addItem(item("Show Touch Bar Preview Window", #selector(togglePreview), key: "p"))
        menu.addItem(item("Re-take Touch Bar", #selector(retake)))
        menu.addItem(item("Lock Keys to Game (⌃⌥⌘K)", #selector(toggleKeyLock), state: KeyCapture.shared.active))
        menu.addItem(item("Hide Menu-Bar Icon (⌃⌥⌘M shows it)", #selector(toggleMenuIcon), state: store.config.hideMenuBarIcon))
        let width = NSMenu()
        width.addItem(item("Auto-detect", #selector(widthAuto), state: store.config.stripWidth == nil))
        width.addItem(item("Narrower (−10pt)", #selector(widthNarrower)))
        width.addItem(item("Wider (+10pt)", #selector(widthWider)))
        let widthItem = NSMenuItem(title: "Strip Width: \(Int(Hardware.shared.touchBarWidth))pt", action: nil, keyEquivalent: "")
        widthItem.submenu = width
        menu.addItem(widthItem)
        menu.addItem(item("Hide Control Strip", #selector(toggleControlStrip), state: store.config.hideControlStrip))
        let themes = NSMenu()
        for t in Theme.all {
            let i = item(t.displayName, #selector(pickTheme(_:)), state: t.name == Theme.named(store.config.theme).name)
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
        addUpdateItems(to: menu)
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

    @objc private func toggleMenuIcon() { mutateConfig { $0.hideMenuBarIcon.toggle() } }
    @objc private func widthAuto() { mutateConfig { $0.stripWidth = nil } }
    @objc private func widthNarrower() { mutateConfig { $0.stripWidth = Double(Hardware.shared.touchBarWidth - 10) } }
    @objc private func widthWider() { mutateConfig { $0.stripWidth = Double(Hardware.shared.touchBarWidth + 10) } }

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
            let size = NSSize(width: Hardware.shared.touchBarWidth * scale, height: 30 * scale)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "widefive — Touch Bar preview  (click = touch · arrows/space = game controls · esc = back)"
            w.contentAspectRatio = size
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            let v = StripView(controller: controller, width: Hardware.shared.touchBarWidth)
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
