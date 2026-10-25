// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortLensCore", targets: ["PortLensCore"]),
        .executable(name: "PortLens", targets: ["PortLens"]),
        .executable(name: "PortLensChecks", targets: ["PortLensChecks"])
    ],
    targets: [
        .target(name: "PortLensCore"),
        .executableTarget(name: "PortLens", dependencies: ["PortLensCore"]),
        .target(
            name: "PortLensValidation",
            dependencies: ["PortLensCore"],
            path: "Tests/PortLensValidation"
        ),
        .executableTarget(name: "PortLensChecks", dependencies: ["PortLensValidation"]),
        .testTarget(name: "PortLensCoreTests", dependencies: ["PortLensValidation"])
    ]
)
