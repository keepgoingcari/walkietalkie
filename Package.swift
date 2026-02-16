// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "walkietalkie",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "walkietalkie", targets: ["walkietalkie"])
    ],
    targets: [
        .executableTarget(
            name: "walkietalkie",
            path: "Sources/walkietalkie"
        )
    ]
)
