// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarKeep",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BarKeep", targets: ["BarKeep"]),
    ],
    targets: [
        .executableTarget(
            name: "BarKeep",
            path: "Sources/BarKeep"
        ),
    ]
)
