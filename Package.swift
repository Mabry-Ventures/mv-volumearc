// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BeastMode",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BeastMode",
            targets: ["BeastMode"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "1.1.0"),
        // Test dependencies
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0"),
    ],
    targets: [
        .target(
            name: "BeastMode",
            dependencies: [
                .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI"),
            ],
            path: "BeastMode"
        ),
        .testTarget(
            name: "BeastModeTests",
            dependencies: [
                "BeastMode",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/BeastModeTests",
            resources: [
                .copy("Snapshots/__Snapshots__")
            ]
        ),
    ]
)
