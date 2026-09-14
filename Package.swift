// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SimpleBlock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SimpleBlockCore"),
        .executableTarget(name: "SimpleBlock", dependencies: ["SimpleBlockCore"]),
        .testTarget(name: "SimpleBlockCoreTests", dependencies: ["SimpleBlockCore"]),
    ]
)
