import AppKit
import ApplicationServices

/// Reads the notification banners currently on screen through Accessibility (the permission widefive already has for
/// key shortcuts). Every agent that posts a macOS notification when it needs you — Chrome/Safari for web agents,
/// Cursor, the Claude and ChatGPT apps, iTerm2/Terminal bells from CLIs — lands here with zero setup.
/// The tree is undocumented and has changed between macOS versions, so this reads defensively: any element under the
/// notification UI whose subrole mentions a notification, or any button with a stacking identifier, is a banner, and
/// its text is whatever description, title, value and static-text children it exposes.
public enum NotificationBanners {
    public struct Banner: Equatable, Hashable {
        /// Stable per notification where macOS gives one (AXIdentifier UUID), else a hash of the text.
        public var id: String
        /// Display name of the posting app, when the banner exposes it ("Google Chrome", "Cursor", "iTerm2").
        public var app: String?
        public var bundleId: String?
        public var text: String
    }

    static let maxNodes = 600

    public static func current() -> [Banner] {
        guard AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return [] }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let windows: [AXUIElement] = attr(app, kAXWindowsAttribute) else { return [] }
        var out: [Banner] = []
        var budget = maxNodes
        for w in windows { walk(w, depth: 0, budget: &budget, into: &out) }
        return out
    }

    private static func walk(_ el: AXUIElement, depth: Int, budget: inout Int, into out: inout [Banner]) {
        guard budget > 0, depth < 10 else { return }
        budget -= 1
        let role: String = attr(el, kAXRoleAttribute) ?? ""
        let subrole: String = attr(el, kAXSubroleAttribute) ?? ""
        let stacking: String? = attr(el, "AXStackingIdentifier")
        // The sidebar list (Notification Center open) is history, not a new alert.
        if subrole == "AXNotificationListItems" { return }
        let isBanner = subrole.hasPrefix("AXNotificationCenter") || (role == kAXButtonRole as String && stacking != nil)
        if isBanner {
            var parts: [String] = []
            var budgetText = 60
            collectText(el, depth: 0, budget: &budgetText, into: &parts)
            var text = parts.joined(separator: " · ")
            if text.isEmpty, let d: String = attr(el, kAXDescriptionAttribute) { text = d }
            let description: String = attr(el, kAXDescriptionAttribute) ?? ""
            var app: String?
            if let comma = description.firstIndex(of: ","), !description.isEmpty {
                let head = description[..<comma].trimmingCharacters(in: .whitespaces)
                if !head.isEmpty, head.count < 40 { app = head }
            }
            var bundle: String?
            if let s = stacking, s.count > 17 { bundle = String(s.dropFirst(17)) }
            if !text.isEmpty {
                let ident: String? = attr(el, kAXIdentifierAttribute)
                let id = (ident?.isEmpty == false) ? ident! : String(text.hashValue)
                out.append(Banner(id: id, app: app, bundleId: bundle, text: text))
            }
            return
        }
        guard let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return }
        for k in kids { walk(k, depth: depth + 1, budget: &budget, into: &out) }
    }

    /// Gathers the banner's own description plus every static-text / title / value underneath it, deduplicated.
    private static func collectText(_ el: AXUIElement, depth: Int, budget: inout Int, into out: inout [String]) {
        guard budget > 0, depth < 6 else { return }
        budget -= 1
        func add(_ s: String?) {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, !out.contains(s) else { return }
            // Descriptions often repeat the children joined by commas; keep the longest distinct pieces only.
            if out.contains(where: { $0.contains(s) }) { return }
            out.removeAll { s.contains($0) }
            out.append(s)
        }
        if depth == 0 { add(attr(el, kAXDescriptionAttribute)) }
        let role: String = attr(el, kAXRoleAttribute) ?? ""
        if role == kAXStaticTextRole as String || depth > 0 {
            add(attr(el, kAXValueAttribute) as String?)
            add(attr(el, kAXTitleAttribute))
            if role == kAXStaticTextRole as String { add(attr(el, kAXDescriptionAttribute)) }
        }
        guard let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return }
        for k in kids { collectText(k, depth: depth + 1, budget: &budget, into: &out) }
    }

    /// The raw accessibility tree of an app (roles, subroles, identifiers, text), for `widefive --ax-dump <bundle id>`.
    public static func dumpTree(bundleId: String, maxDepth: Int = 12) -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return "\(bundleId) not running" }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        var lines: [String] = ["\(bundleId) pid \(app.processIdentifier) trusted=\(AXIsProcessTrusted())"]
        var budget = 2000
        func visit(_ el: AXUIElement, _ depth: Int) {
            guard budget > 0, depth <= maxDepth else { return }
            budget -= 1
            var names: CFArray?
            AXUIElementCopyAttributeNames(el, &names)
            let attrs = (names as? [String]) ?? []
            func str(_ k: String) -> String? {
                guard let v: CFTypeRef = attr(el, k) else { return nil }
                if let s = v as? String { return s.isEmpty ? nil : String(s.prefix(100)) }
                if let a = v as? NSAttributedString { return String(a.string.prefix(100)) }
                return nil
            }
            var parts = [str(kAXRoleAttribute) ?? "?"]
            if let v = str(kAXSubroleAttribute) { parts.append("sub=\(v)") }
            if let v = str(kAXIdentifierAttribute) { parts.append("id=\(v)") }
            if let v = str(kAXTitleAttribute) { parts.append("title=\(v)") }
            if let v = str(kAXDescriptionAttribute) { parts.append("desc=\(v)") }
            if let v = str(kAXValueAttribute) { parts.append("value=\(v)") }
            for k in ["AXStackingIdentifier", "AXAttributedDescription"] where attrs.contains(k) {
                if let v = str(k) { parts.append("\(k)=\(v)") }
            }
            lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
            guard let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return }
            for k in kids { visit(k, depth + 1) }
        }
        visit(root, 0)
        return lines.joined(separator: "\n")
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
}
