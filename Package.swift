// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iCONIQ",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "iCONIQCore", swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "iCONIQ", dependencies: ["iCONIQCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "iCONIQCoreTests", dependencies: ["iCONIQCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
