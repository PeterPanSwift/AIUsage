// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIUsage",
    platforms: [.macOS("27.0")],
    products: [.library(name: "UsageCore", targets: ["UsageCore"]),
               .executable(name: "usage-probe", targets: ["UsageProbe"])],
    targets: [
        .target(name: "UsageCore", path: "Sources/Core"),
        .executableTarget(name: "UsageProbe", dependencies: ["UsageCore"], path: "Sources/Probe"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], path: "Tests")
    ]
)
