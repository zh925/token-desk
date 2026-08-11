// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenDeskKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenDeskCore", targets: ["TokenDeskCore"]),
        .library(name: "TokenDeskData", targets: ["TokenDeskData"]),
        .library(name: "TokenDeskConnectors", targets: ["TokenDeskConnectors"]),
        .library(name: "TokenDeskPlatform", targets: ["TokenDeskPlatform"]),
        .library(name: "TokenDeskDesign", targets: ["TokenDeskDesign"]),
        .library(name: "TokenDeskFeatures", targets: ["TokenDeskFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(name: "TokenDeskCore"),
        .target(
            name: "TokenDeskData",
            dependencies: [
                "TokenDeskCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "TokenDeskConnectors", dependencies: ["TokenDeskCore"]),
        .target(name: "TokenDeskPlatform", dependencies: ["TokenDeskCore"]),
        .target(name: "TokenDeskDesign", dependencies: ["TokenDeskCore"]),
        .target(
            name: "TokenDeskFeatures",
            dependencies: ["TokenDeskCore", "TokenDeskDesign"]
        ),
        .testTarget(name: "TokenDeskCoreTests", dependencies: ["TokenDeskCore"]),
        .testTarget(
            name: "TokenDeskDataTests",
            dependencies: [
                "TokenDeskData",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "TokenDeskConnectorsTests",
            dependencies: ["TokenDeskConnectors", "TokenDeskCore"]
        ),
        .testTarget(name: "TokenDeskPlatformTests", dependencies: ["TokenDeskPlatform"]),
        .testTarget(name: "TokenDeskDesignTests", dependencies: ["TokenDeskDesign"]),
        .testTarget(name: "TokenDeskFeaturesTests", dependencies: ["TokenDeskFeatures"]),
    ],
    swiftLanguageModes: [.v6]
)
