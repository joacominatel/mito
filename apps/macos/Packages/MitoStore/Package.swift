// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MitoStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MitoStore", targets: ["MitoStore"]),
    ],
    dependencies: [
        .package(path: "../MitoCore"),
    ],
    targets: [
        .target(name: "MitoStore", dependencies: ["MitoCore"]),
        .testTarget(name: "MitoStoreTests", dependencies: ["MitoStore"]),
    ]
)
