// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanDockCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CleanDockCore", targets: ["CleanDockCore"])
    ],
    targets: [
        .target(name: "CleanDockCore"),
        .testTarget(
            name: "CleanDockCoreTests",
            dependencies: ["CleanDockCore"]
        )
    ]
)
