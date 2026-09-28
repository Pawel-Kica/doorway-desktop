// swift-tools-version:5.10
// Only the pure logic in Core, so `swift test` runs it on the Mac. The iPhone app itself is SimpleBlock.xcodeproj.
import PackageDescription

let package = Package(
    name: "SimpleBlockMobile",
    platforms: [.macOS(.v14), .iOS("26.0")],
    targets: [
        .target(name: "SimpleBlockMobileCore", path: "Core"),
        .testTarget(name: "SimpleBlockMobileCoreTests", dependencies: ["SimpleBlockMobileCore"], path: "CoreTests"),
    ]
)
