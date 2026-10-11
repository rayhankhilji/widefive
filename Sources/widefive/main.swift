import AppKit
import WideFiveKit

let args = CommandLine.arguments

if args.contains("--version") {
    print("widefive \(Updater.versionDescription)")
    exit(0)
}

if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
    _ = NSApplication.shared
    let mode = args[i + 1], out = args[i + 2]
    let secs = args.count > i + 3 ? Double(args[i + 3]) ?? 1.5 : 1.5
    let width = args.count > i + 4 ? CGFloat(Double(args[i + 4]) ?? 1085) : Hardware.shared.touchBarWidth
    guard let png = Snapshot.render(mode: mode, seconds: secs, width: width) else { fputs("render failed\n", stderr); exit(1) }
    try png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

if args.contains("--print-default-config") {
    print(String(data: try Config.default.encoded(), encoding: .utf8)!)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.openPreviewOnLaunch = args.contains("--preview")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
