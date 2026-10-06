// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DoorwayDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DoorwayDesktopCore"),
        .executableTarget(name: "DoorwayDesktop", dependencies: ["DoorwayDesktopCore"]),
        .testTarget(name: "DoorwayDesktopCoreTests", dependencies: ["DoorwayDesktopCore"]),
    ]
)
