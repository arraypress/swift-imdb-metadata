// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IMDbMetadata",
    platforms: [.macOS(.v13)],
    products: [.library(name: "IMDbMetadata", targets: ["IMDbMetadata"])],
    targets: [
        .target(name: "IMDbMetadata"),
        .testTarget(name: "IMDbMetadataTests", dependencies: ["IMDbMetadata"]),
    ]
)
