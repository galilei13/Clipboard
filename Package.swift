// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clipboard", targets: ["ClipboardApp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ClipboardCore", dependencies: ["CSQLite"]),
        .target(name: "ClipboardPlatform", dependencies: ["ClipboardCore"]),
        .executableTarget(name: "ClipboardApp", dependencies: ["ClipboardCore", "ClipboardPlatform"]),
        .executableTarget(name: "ClipboardChecks", dependencies: ["ClipboardCore", "ClipboardPlatform"], path: "Tests/ClipboardChecks")
    ]
)
