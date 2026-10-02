// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BoardCore",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [.library(name: "BoardCore", targets: ["BoardCore"])],
    targets: [
        .target(name: "BoardCore"),
        .testTarget(
            name: "BoardCoreTests",
            dependencies: ["BoardCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
