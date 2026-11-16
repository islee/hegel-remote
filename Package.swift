// swift-tools-version: 6.0
// HegelKit: protocol + networking core for the Volum remote (Hegel amplifiers, TCP 50001).
// No third-party dependencies; Swift 6 language mode (strict concurrency) for every target.
//
// Portability: HegelProtocol is Foundation-only and must build on Linux (a future Docker web app
// will reuse it). HegelClient, HegelDiscovery and hegelctl use Network.framework, so they are Apple-only
// and are declared only when the manifest is evaluated on a non-Linux host.
import PackageDescription

var products: [Product] = [
    .library(name: "HegelProtocol", targets: ["HegelProtocol"]),
]
var targets: [Target] = [
    .target(name: "HegelProtocol"),
    .testTarget(name: "HegelProtocolTests", dependencies: ["HegelProtocol"]),
]

#if !os(Linux)
products += [
    .library(name: "HegelClient", targets: ["HegelClient"]),
    .library(name: "HegelDiscovery", targets: ["HegelDiscovery"]),
    .executable(name: "hegelctl", targets: ["hegelctl"]),
]
targets += [
    .target(name: "HegelClient", dependencies: ["HegelProtocol"]),
    .target(name: "HegelDiscovery", dependencies: ["HegelProtocol", "HegelClient"]),
    .executableTarget(name: "hegelctl", dependencies: ["HegelProtocol", "HegelClient", "HegelDiscovery"]),
    .testTarget(name: "HegelClientTests", dependencies: ["HegelProtocol", "HegelClient"]),
    .testTarget(name: "HegelDiscoveryTests", dependencies: ["HegelProtocol", "HegelDiscovery"]),
]
#endif

let package = Package(
    name: "HegelKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
