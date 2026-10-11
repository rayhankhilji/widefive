import AppKit
import Sparkle

/// Sparkle 2 auto-updater. Only runs inside a packaged widefive.app that carries a feed URL and an
/// EdDSA public key; from `swift run` / `.build/release/widefive` it stays off and says why.
public final class Updater: NSObject {
    public static let shared = Updater()

    private var controller: SPUStandardUpdaterController?
    /// Why updates are off, or nil when the updater is running.
    public private(set) var disabledReason: String?
    /// Version of an update Sparkle found in the background but hasn't shown yet.
    public private(set) var pendingVersion: String?
    /// Called on the main thread when a background check finds an update.
    public var onUpdateFound: ((String) -> Void)?

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    public static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// "0.2.0 (57)" in a packaged app, "dev (from source)" otherwise.
    public static var versionDescription: String {
        guard isPackagedApp else { return "dev (from source)" }
        return build.map { "\(version) (\($0))" } ?? version
    }

    public static var isPackagedApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static func configurationProblem(info: [String: Any]?, isPackagedApp: Bool) -> String? {
        guard isPackagedApp else { return "running from source" }
        let feed = (info?["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let isLocal = ["127.0.0.1", "localhost"].contains(feed?.host ?? "")
        guard let feed, feed.scheme == "https" || (feed.scheme == "http" && isLocal) else { return "no update feed in this build" }
        let key = (info?["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard Data(base64Encoded: key)?.count == 32 else { return "this build has no update signing key" }
        return nil
    }

    public var isEnabled: Bool { controller != nil }

    public func start() {
        guard controller == nil else { return }
        if let problem = Self.configurationProblem(info: Bundle.main.infoDictionary, isPackagedApp: Self.isPackagedApp) {
            disabledReason = problem
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        disabledReason = nil
    }

    public var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    public func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    public var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    public var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }
}

extension Updater: SPUUpdaterDelegate {
    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async { self.pendingVersion = item.displayVersionString }
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async { self.pendingVersion = nil }
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    // widefive has no Dock icon, so background finds become a Touch Bar toast + menu badge
    // instead of a window popping up over whatever you're doing.
    public var supportsGentleScheduledUpdateReminders: Bool { true }

    public func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    public func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        pendingVersion = update.displayVersionString
        if !state.userInitiated { onUpdateFound?(update.displayVersionString) }
    }

    public func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}
