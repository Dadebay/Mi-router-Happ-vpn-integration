// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HappRouter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HappRouter", targets: ["HappRouterApp"])],
    targets: [.executableTarget(name: "HappRouterApp", path: "Sources/HappRouterApp")]
)
