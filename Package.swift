// swift-tools-version: 6.0
// HegelKit: protocol + networking core for hegel-remote (Hegel amplifiers, TCP 50001).
// No third-party dependencies; Swift 6 language mode (strict concurrency) for every target.
//
// Portability: HegelProtocol is Foundation-only and must build on Linux (a future Docker web app
// will reuse it). HegelClient, HegelDiscovery, hegelctl and the development-only HegelFakeAmp / fakeamp use
// Network.framework, so they are Apple-only and are declared only when the manifest is evaluated on a non-Linux host.
// HegelRemoteCore is the apps' logic layer (Apple-only: Observation, Network via HegelClient). The SwiftUI apps live
// outside this package (App/, project.yml) and depend on its products.
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
    // Development only: an in-process H590 emulator (tests, app tests) and the same as a process (`swift run fakeamp`).
    .library(name: "HegelFakeAmp", targets: ["HegelFakeAmp"]),
    .executable(name: "fakeamp", targets: ["fakeamp"]),
    // The apps' logic layer (controller, settings, skins, playback drivers): no SwiftUI, tested here and in Xcode.
    .library(name: "HegelRemoteCore", targets: ["HegelRemoteCore"]),
]
targets += [
    .target(name: "HegelClient", dependencies: ["HegelProtocol"]),
    .target(name: "HegelDiscovery", dependencies: ["HegelProtocol", "HegelClient"]),
    .executableTarget(name: "hegelctl", dependencies: ["HegelProtocol", "HegelClient", "HegelDiscovery"]),
    .target(name: "HegelFakeAmp"),
    .executableTarget(name: "fakeamp", dependencies: ["HegelFakeAmp"]),
    .testTarget(name: "HegelClientTests", dependencies: ["HegelProtocol", "HegelClient", "HegelFakeAmp"]),
    .target(name: "HegelRemoteCore", dependencies: ["HegelProtocol", "HegelClient"]),
    .testTarget(name: "HegelRemoteCoreTests", dependencies: ["HegelRemoteCore", "HegelProtocol", "HegelClient", "HegelFakeAmp"]),
    .testTarget(name: "HegelDiscoveryTests", dependencies: ["HegelProtocol", "HegelDiscovery"]),
]
#endif

let package = Package(
    name: "HegelKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
