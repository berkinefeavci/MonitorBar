// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonitorBar",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MonitorBar", targets: ["MonitorBar"])],
    targets: [
        .executableTarget(name: "MonitorBar"),
        .testTarget(name: "MonitorBarTests", dependencies: ["MonitorBar"]),
    ]
)
