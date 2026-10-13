// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JC2Mac",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "JC2Mac", targets: ["JC2Mac"])],
    targets: [
        .target(name: "JC2Core"),
        .executableTarget(name: "JC2Mac", dependencies: ["JC2Core"]),
        .testTarget(name: "JC2CoreTests", dependencies: ["JC2Core"])
    ],
    swiftLanguageModes: [.v5]
)
