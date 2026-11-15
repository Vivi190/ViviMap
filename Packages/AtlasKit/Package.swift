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
            targets: [
                "AppCore", "DesignSystem", "LocationEngine", "MapEngine", "Diagnostics",
                "SearchEngine", "RoutingEngine", "NavigationEngine", "TrafficEngine", "RoadHazards", "TripHistory",
                "NavigationActivity",
            ]
        ),
        // The widget extension links only the Live Activity attributes, not the map or routing stack.
        .library(name: "AtlasActivity", targets: ["NavigationActivity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", from: "7.0.0"),
        // 0.x releases can break API: pin exactly. Ferrostar (Phase 2) accepts >= 0.26.1.
        .package(url: "https://github.com/maplibre/swiftui-dsl", exact: "0.27.0"),
        // Only FerrostarCore is used (routing + navigation state); its MapLibre UI is not, so the
        // swiftui-dsl 0.26 vs 0.27 question (docs/architecture.md, ADR-3) does not arise.
        .package(url: "https://github.com/stadiamaps/ferrostar", exact: "0.59.0"),
        // On-device Valhalla 3.9.0 for offline routing (MIT); its tiles come from .github/workflows/offline-data.yml.
        .package(url: "https://github.com/Rallista/valhalla-mobile.git", exact: "0.6.4"),
        // ValhallaConfig lives here; same range valhalla-mobile 0.6.4 asks for.
        .package(url: "https://github.com/Rallista/valhalla-openapi-models-swift.git", .upToNextMinor(from: "0.6.0")),
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
        .target(
            name: "RoutingEngine",
            dependencies: [
                "SearchEngine",
                .product(name: "FerrostarCore", package: "ferrostar"),
                .product(name: "Valhalla", package: "valhalla-mobile"),
                .product(name: "ValhallaConfigModels", package: "valhalla-openapi-models-swift"),
            ]
        ),
        .target(
            name: "NavigationEngine",
            dependencies: ["RoutingEngine", "RoadHazards", "SearchEngine", .product(name: "FerrostarCore", package: "ferrostar")]
        ),
        .target(name: "TrafficEngine"),
        // Cameras and bumps from OSM, refreshed with Tools/hazards/fetch_hazards.py.
        .target(name: "RoadHazards", resources: [.copy("Resources/hazards-istanbul.json"), .copy("Resources/signals-istanbul.json")]),
        .target(name: "TripHistory"),
        .target(name: "NavigationActivity"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .testTarget(name: "LocationEngineTests", dependencies: ["LocationEngine"]),
        .testTarget(name: "SearchEngineTests", dependencies: ["SearchEngine"], resources: [.copy("Fixtures")]),
        .testTarget(
            name: "RoutingEngineTests",
            dependencies: ["RoutingEngine", "SearchEngine", .product(name: "FerrostarCore", package: "ferrostar")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TrafficEngineTests", dependencies: ["TrafficEngine"], resources: [.copy("Fixtures")]),
        .testTarget(name: "TripHistoryTests", dependencies: ["TripHistory"]),
        .testTarget(name: "MapEngineTests", dependencies: ["MapEngine"]),
        .testTarget(
            name: "NavigationEngineTests",
            dependencies: ["NavigationEngine", "RoutingEngine", "SearchEngine", "RoadHazards", .product(name: "FerrostarCore", package: "ferrostar")]
        ),
    ]
)
