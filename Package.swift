// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iCONIQ",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Moteur de rendu de MiCONE (dépôt voisin), utilisé par le serveur MCP pour fabriquer les icônes.
        .package(path: "../MiCONE"),
    ],
    targets: [
        .target(name: "iCONIQCore", swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "IconiqMCPCore", dependencies: ["iCONIQCore", .product(name: "MiCONECore", package: "MiCONE")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "iconiq-mcp", dependencies: ["IconiqMCPCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "iCONIQ", dependencies: ["iCONIQCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "iCONIQCoreTests", dependencies: ["iCONIQCore", "IconiqMCPCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
