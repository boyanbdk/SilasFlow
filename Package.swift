// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SilasFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SilasFlow", targets: ["SilasFlow"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // NOTE: sindresorhus/KeyboardShortcuts was dropped — its #Preview macros
        // don't build under Command Line Tools (no PreviewsMacros plugin).
        // We register the hotkey directly with Carbon RegisterEventHotKey instead.
    ],
    targets: [
        .executableTarget(
            name: "SilasFlow",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/SilasFlow",
            swiftSettings: [
                // Our own code opts into Swift 5 language mode to avoid strict-
                // concurrency friction with AppKit/Carbon callback APIs.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
