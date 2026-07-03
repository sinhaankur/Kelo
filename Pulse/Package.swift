// swift-tools-version: 5.9
import PackageDescription

// PulseKit (core) and the terminal dashboard build everywhere (macOS + Linux);
// the SwiftUI app target only exists on macOS.
var targets: [Target] = [
    .target(name: "PulseKit", path: "Sources/PulseKit"),
    .executableTarget(
        name: "PulseTUI",
        dependencies: ["PulseKit"],
        path: "Sources/PulseTUI"
    ),
]
var products: [Product] = [
    .executable(name: "pulse-tui", targets: ["PulseTUI"]),
]

#if os(macOS)
targets.append(.executableTarget(
    name: "Pulse",
    dependencies: ["PulseKit"],
    path: "Sources/PulseApp",
    linkerSettings: [
        .linkedFramework("Vision"),
        .linkedFramework("LocalAuthentication"),
    ]
))
products.append(.executable(name: "Pulse", targets: ["Pulse"]))
#endif

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
