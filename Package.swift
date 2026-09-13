// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clipboard", targets: ["ClipboardApp"])],
    targets: [
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip", checksum: "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "ClipboardCore", dependencies: ["CSQLite"]),
        .target(name: "ClipboardPlatform", dependencies: ["ClipboardCore"]),
        .executableTarget(name: "ClipboardApp", dependencies: ["ClipboardCore", "ClipboardPlatform", "Sparkle"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "ClipboardChecks", dependencies: ["ClipboardCore", "ClipboardPlatform"], path: "Tests/ClipboardChecks")
    ]
)
