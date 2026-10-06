// swift-tools-version:5.10
// Only the pure logic in Core, so `swift test` runs it on the Mac. The iPhone app itself is Doorway.xcodeproj.
import PackageDescription

let package = Package(
    name: "DoorwayMobile",
    platforms: [.macOS(.v14), .iOS("26.0")],
    targets: [
        .target(name: "DoorwayMobileCore", path: "Core"),
        .testTarget(name: "DoorwayMobileCoreTests", dependencies: ["DoorwayMobileCore"], path: "CoreTests"),
    ]
)
