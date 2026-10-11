import AppKit

/// Figures out which Mac this is and how wide its Touch Bar actually is.
///
/// Macs with a physical Esc key (2019 16", 2020 13"/13" 4-port, 2020 16") have a shorter strip than the
/// 2016–2018 models whose Esc lives on the bar itself. Drawing 1085pt of content on a 1004pt bar is what
/// made the right-hand side look cropped.
public final class Hardware {
    public static let shared = Hardware()

    public let modelIdentifier: String
    public let marketingName: String
    public let hasPhysicalEsc: Bool
    public let isAppleSilicon: Bool
    /// Width of the usable Touch Bar area in points (the bar is 30pt tall, 2x scale).
    public private(set) var touchBarWidth: CGFloat

    private init() {
        modelIdentifier = Hardware.sysctl("hw.model") ?? ""
        #if arch(arm64)
        isAppleSilicon = true
        #else
        isAppleSilicon = Hardware.sysctl("machdep.cpu.brand_string")?.contains("Apple") ?? false
        #endif
        let m = modelIdentifier
        // MacBookPro15,x (2018/19) and earlier put Esc on the bar. 16,1 (16" 2019) and 16,2/16,3/16,4 (2020) have a real Esc key.
        let majorMinor = Hardware.version(m)
        hasPhysicalEsc = m.hasPrefix("MacBookPro") && majorMinor.major >= 16
        touchBarWidth = hasPhysicalEsc ? 1004 : 1085
        marketingName = Hardware.name(for: m, major: majorMinor.major, minor: majorMinor.minor)
    }

    public func overrideWidth(_ w: CGFloat?) { touchBarWidth = w ?? (hasPhysicalEsc ? 1004 : 1085) }

    /// Called once the bar tells us its real size, so an unknown model self-corrects.
    public func learnedActualWidth(_ w: CGFloat) {
        guard w > 400, abs(w - touchBarWidth) > 1 else { return }
        touchBarWidth = w
    }

    public var summary: String { "\(marketingName) · \(modelIdentifier) · strip \(Int(touchBarWidth))pt" }

    private static func version(_ model: String) -> (major: Int, minor: Int) {
        let digits = model.drop { !$0.isNumber }
        let parts = digits.split(separator: ",")
        return (Int(parts.first ?? "0") ?? 0, parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
    }

    private static func name(for model: String, major: Int, minor: Int) -> String {
        guard model.hasPrefix("MacBookPro") else { return model.isEmpty ? "Unknown Mac" : model }
        switch (major, minor) {
        case (13, 2), (13, 3): return "MacBook Pro (2016, Touch Bar)"
        case (14, 2), (14, 3): return "MacBook Pro (2017, Touch Bar)"
        case (15, 1), (15, 3): return "MacBook Pro 15\" (2018–19)"
        case (15, 2), (15, 4): return "MacBook Pro 13\" (2018–19)"
        case (16, 1), (16, 4): return "MacBook Pro 16\" (2019–20)"
        case (16, 2): return "MacBook Pro 13\" (2020, four Thunderbolt ports)"
        case (16, 3): return "MacBook Pro 13\" (2020, two Thunderbolt ports)"
        case (17, _), (18, _): return "MacBook Pro (Apple silicon, no Touch Bar)"
        default: return model
        }
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
