// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .strictMemorySafety(),
]

let modules: [(name: String, dependencies: [Target.Dependency])] = [
    ("MitoCore", []),
    ("LCUKit", ["MitoCore"]),
    ("MitoStore", ["MitoCore", .product(name: "GRDB", package: "GRDB.swift")]),
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
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies,
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
