// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarKeep",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BarKeep", targets: ["BarKeep"]),
        .library(name: "BarKeepCore", targets: ["BarKeepCore"]),
    ],
    targets: [
        .target(
            name: "BarKeepCore",
            path: "Sources/BarKeepCore"
        ),
        .executableTarget(
            name: "BarKeep",
            dependencies: ["BarKeepCore"],
            path: "Sources/BarKeep"
        ),
        .testTarget(
            name: "BarKeepTests",
            dependencies: ["BarKeepCore"],
            path: "Tests/BarKeepTests"
        ),
    ]
)
