// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonitorBar",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MonitorBar", targets: ["MonitorBar"])],
    targets: [
        .target(name: "DDCBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MonitorBar", dependencies: ["DDCBridge"]),
        .testTarget(name: "MonitorBarTests", dependencies: ["MonitorBar", "DDCBridge"]),
    ]
)
