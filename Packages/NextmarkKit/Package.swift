// swift-tools-version: 6.2
import PackageDescription

// Shared code for the Nextmark app and its extensions.
// Dependency rule (Docs/architecture.md §10): extensions link only Model,
// Capture, CaptureUI and DesignSystem — never Library, Intelligence or Pipeline.
let package = Package(
    name: "NextmarkKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Model", targets: ["Model"]),
        .library(name: "Capture", targets: ["Capture"]),
        .library(name: "CaptureUI", targets: ["CaptureUI"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Library", targets: ["Library"]),
        .library(name: "Extraction", targets: ["Extraction"]),
        .library(name: "Intelligence", targets: ["Intelligence"]),
        .library(name: "Pipeline", targets: ["Pipeline"]),
        .library(name: "Search", targets: ["Search"]),
        .library(name: "Grouping", targets: ["Grouping"]),
        .library(name: "Moments", targets: ["Moments"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Extension-safe
        .target(name: "Model"),
        .target(name: "Capture", dependencies: ["Model"]),
        .target(name: "DesignSystem", dependencies: ["Model"]),
        .target(name: "CaptureUI", dependencies: ["Model", "Capture", "DesignSystem"]),

        // App only
        .target(
            name: "Library",
            dependencies: ["Model", "Capture", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "Extraction", dependencies: ["Model"]),
        .target(name: "Intelligence", dependencies: ["Model"]),
        .target(name: "Pipeline", dependencies: ["Model", "Library", "Extraction", "Intelligence", "Search", "Grouping"]),
        .target(name: "Search", dependencies: ["Model", "Library", "Intelligence"]),
        .target(name: "Grouping", dependencies: ["Model", "Search"]),
        .target(name: "Moments", dependencies: ["Model", "Library"]),
        .target(name: "Features", dependencies: ["Model", "Library", "Intelligence", "Search", "Moments", "DesignSystem"]),

        .testTarget(name: "ModelTests", dependencies: ["Model"]),
        .testTarget(name: "CaptureTests", dependencies: ["Model", "Capture"]),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Model", "Capture", "Library", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "ExtractionTests", dependencies: ["Model", "Extraction"]),
        .testTarget(name: "PipelineTests", dependencies: ["Model", "Capture", "Library", "Extraction", "Intelligence", "Pipeline"]),
        .testTarget(name: "IntelligenceTests", dependencies: ["Model", "Intelligence"]),
        .testTarget(
            name: "SearchTests",
            dependencies: ["Model", "Library", "Intelligence", "Search", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "GroupingTests", dependencies: ["Grouping", "Search"]),
        .testTarget(
            name: "MomentsTests",
            dependencies: ["Moments", "Model", "Library", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
