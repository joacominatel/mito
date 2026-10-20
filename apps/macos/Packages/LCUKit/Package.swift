// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LCUKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LCUKit", targets: ["LCUKit"]),
    ],
    dependencies: [
        .package(path: "../MitoCore"),
    ],
    targets: [
        .target(name: "LCUKit", dependencies: ["MitoCore"]),
        .testTarget(name: "LCUKitTests", dependencies: ["LCUKit"]),
    ]
)
