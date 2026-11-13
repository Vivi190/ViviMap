// swift-tools-version: 6.2
import PackageDescription

// Modules are added phase by phase (see docs/development-plan.md) instead of shipping empty shells.
let package = Package(
    name: "AtlasKit",
    defaultLocalization: "tr",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "AtlasKit",
            targets: ["AppCore", "DesignSystem", "LocationEngine", "MapEngine", "Diagnostics", "SearchEngine"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", from: "7.0.0"),
        // 0.x releases can break API: pin exactly. Ferrostar (Phase 2) accepts >= 0.26.1.
        .package(url: "https://github.com/maplibre/swiftui-dsl", exact: "0.27.0"),
    ],
    targets: [
        .target(name: "AppCore"),
        .target(name: "DesignSystem"),
        .target(name: "LocationEngine"),
        .target(
            name: "MapEngine",
            dependencies: [
                "DesignSystem",
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
                .product(name: "MapLibreSwiftUI", package: "swiftui-dsl"),
                .product(name: "MapLibreSwiftDSL", package: "swiftui-dsl"),
            ],
            resources: [.copy("Styles")]
        ),
        .target(name: "Diagnostics", dependencies: ["DesignSystem", "LocationEngine"]),
        .target(name: "SearchEngine"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .testTarget(name: "LocationEngineTests", dependencies: ["LocationEngine"]),
        .testTarget(name: "SearchEngineTests", dependencies: ["SearchEngine"], resources: [.copy("Fixtures")]),
    ]
)
