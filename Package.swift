// swift-tools-version:5.9
// Builds and tests the platform-independent core on any OS (including Linux CI).
// The iOS app itself is generated from project.yml with XcodeGen and compiles these same files.
import PackageDescription

let package = Package(
    name: "AirFieldCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AirFieldCore", targets: ["AirFieldCore"])],
    targets: [
        .target(name: "AirFieldCore", path: "AirField/Core"),
        .testTarget(name: "AirFieldCoreTests", dependencies: ["AirFieldCore"], path: "Tests/AirFieldCoreTests", exclude: ["Samples"]),
    ]
)
