// swift-tools-version: 5.8
import PackageDescription
let package = Package(
    name: "GRCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "GRCore", targets: ["GRCore"])],
    targets: [
        .target(name: "GRCore", path: "GRTransfer/Core"),
        .testTarget(name: "GRCoreTests", dependencies: ["GRCore"], path: "Tests/GRCoreTests")
    ]
)
