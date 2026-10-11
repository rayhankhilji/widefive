import AppKit

/// Full-colour logos for buttons. "app:<bundle id>" uses the installed app's icon, "web:<domain>" a favicon
/// cached in ~/.widefive/icons. Chain fallbacks with "|", e.g. "app:com.anthropic.claudefordesktop|web:claude.ai".
public final class LogoCache {
    public struct Logo {
        public let image: NSImage
        public let isAppIcon: Bool
    }

    public static let shared = LogoCache()
    static let directory = ConfigStore.directory.appendingPathComponent("icons")
    private var logos: [String: Logo] = [:]
    private var requested: Set<String> = []

    public func logo(_ spec: String) -> Logo? {
        if let l = logos[spec] { return l }
        for part in spec.split(separator: "|").map(String.init) {
            if let l = resolve(part) { logos[spec] = l; return l }
        }
        return nil
    }

    private func resolve(_ part: String) -> Logo? {
        if part.hasPrefix("app:") {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: String(part.dropFirst(4))) else { return nil }
            return Logo(image: NSWorkspace.shared.icon(forFile: url.path), isAppIcon: true)
        }
        if part.hasPrefix("web:") {
            let domain = String(part.dropFirst(4))
            let file = Self.directory.appendingPathComponent("\(domain).png")
            if let img = NSImage(contentsOf: file), img.isValid { return Logo(image: img, isAppIcon: false) }
            fetch(domain, to: file)
        }
        return nil
    }

    /// One attempt per launch; the button shows its SF Symbol fallback until the favicon lands.
    private func fetch(_ domain: String, to file: URL) {
        guard !requested.contains(domain),
              let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") else { return }
        requested.insert(domain)
        URLSession.shared.dataTask(with: url) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200, NSImage(data: data) != nil else { return }
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: file)
        }.resume()
    }
}
