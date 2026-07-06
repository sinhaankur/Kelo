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
    .testTarget(
        name: "PulseKitTests",
        dependencies: ["PulseKit"],
        path: "Tests/PulseKitTests"
    ),
]
var products: [Product] = [
    .executable(name: "pulse-tui", targets: ["PulseTUI"]),
    // Shared pure-logic core, linked by the iOS/iPadOS app (generated via
    // xcodegen) so every platform runs the exact same PulseKit.
    .library(name: "PulseKit", targets: ["PulseKit"]),
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
    // PulseKit is pure Foundation, so it builds for every Apple platform;
    // the SwiftUI Pulse app target stays macOS-gated above. iOS/iPadOS get
    // their own app target from the xcodegen spec, linking PulseKit.
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: products,
    targets: targets
)
