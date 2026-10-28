// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipline",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clipline", targets: ["Clipline"])],
    targets: [
        .executableTarget(name: "Clipline"),
        .testTarget(name: "CliplineTests", dependencies: ["Clipline"])
    ]
)
