// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MitoAssets",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MitoAssets", targets: ["MitoAssets"]),
    ],
    dependencies: [
        .package(path: "../MitoCore"),
        .package(path: "../LCUKit"),
    ],
    targets: [
        .target(name: "MitoAssets", dependencies: ["MitoCore", "LCUKit"]),
        .testTarget(name: "MitoAssetsTests", dependencies: ["MitoAssets"]),
    ]
)
