// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MitoEngine",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MitoEngine", targets: ["MitoEngine"]),
    ],
    dependencies: [
        .package(path: "../MitoCore"),
    ],
    targets: [
        .target(name: "MitoEngine", dependencies: ["MitoCore"]),
        .testTarget(name: "MitoEngineTests", dependencies: ["MitoEngine"]),
    ]
)
