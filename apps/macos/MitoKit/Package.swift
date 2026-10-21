// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .strictMemorySafety(),
]

let modules: [(name: String, dependencies: [String])] = [
    ("MitoCore", []),
    ("LCUKit", ["MitoCore"]),
    ("MitoStore", ["MitoCore"]),
    ("MitoEngine", ["MitoCore"]),
    ("MitoAssets", ["MitoCore", "LCUKit"]),
    ("MitoImport", ["MitoCore", "LCUKit"]),
]

let testSupport: (name: String, dependencies: [String]) = (
    "MitoTestSupport", ["MitoCore", "LCUKit"]
)

let package = Package(
    name: "MitoKit",
    platforms: [.macOS(.v15)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies.map { .target(name: $0) },
                swiftSettings: swiftSettings
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: [.target(name: module.name), .target(name: testSupport.name)],
                swiftSettings: swiftSettings
            ),
        ]
    } + [
        .target(
            name: testSupport.name,
            dependencies: testSupport.dependencies.map { .target(name: $0) },
            path: "Tests/\(testSupport.name)",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ArchitectureTests",
            swiftSettings: swiftSettings
        ),
    ]
)
