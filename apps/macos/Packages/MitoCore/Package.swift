// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MitoCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MitoCore", targets: ["MitoCore"]),
    ],
    targets: [
        .target(name: "MitoCore"),
        .testTarget(name: "MitoCoreTests", dependencies: ["MitoCore"]),
    ]
)
