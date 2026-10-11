// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "widefive",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "widefive", targets: ["widefive"]),
        .library(name: "WideFiveKit", targets: ["WideFiveKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "WideFiveKit",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(name: "widefive", dependencies: ["WideFiveKit"]),
        .testTarget(name: "WideFiveKitTests", dependencies: ["WideFiveKit"]),
    ]
)
