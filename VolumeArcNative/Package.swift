// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VolumeArcNative",
    platforms: [
        .iOS(.v26),
        .watchOS("26.4"),
    ],
    products: [
        .library(name: "VolumeArcCore", type: .static, targets: ["VolumeArcCore"]),
        .library(name: "VolumeArcUI", type: .static, targets: ["VolumeArcUI"]),
    ],
    targets: [
        .target(name: "VolumeArcCore"),
        .target(name: "VolumeArcUI", dependencies: ["VolumeArcCore"]),
        .testTarget(name: "VolumeArcCoreTests", dependencies: ["VolumeArcCore"]),
    ]
)
