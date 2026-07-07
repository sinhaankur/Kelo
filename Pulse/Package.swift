// swift-tools-version: 5.9
import PackageDescription

// KeloKit (core) and the terminal dashboard build everywhere (macOS + Linux);
// the SwiftUI app target only exists on macOS.
var targets: [Target] = [
    .target(name: "KeloKit", path: "Sources/KeloKit"),
    .executableTarget(
        name: "KeloTUI",
        dependencies: ["KeloKit"],
        path: "Sources/KeloTUI"
    ),
    .testTarget(
        name: "KeloKitTests",
        dependencies: ["KeloKit"],
        path: "Tests/KeloKitTests"
    ),
]
var products: [Product] = [
    .executable(name: "kelo-tui", targets: ["KeloTUI"]),
    // Shared pure-logic core, linked by the iOS/iPadOS app (generated via
    // xcodegen) so every platform runs the exact same KeloKit.
    .library(name: "KeloKit", targets: ["KeloKit"]),
]

#if os(macOS)
targets.append(.executableTarget(
    name: "Kelo",
    dependencies: ["KeloKit"],
    path: "Sources/KeloApp",
    linkerSettings: [
        .linkedFramework("Vision"),
        .linkedFramework("LocalAuthentication"),
    ]
))
products.append(.executable(name: "Kelo", targets: ["Kelo"]))
#endif

let package = Package(
    name: "Kelo",
    // KeloKit is pure Foundation, so it builds for every Apple platform;
    // the SwiftUI Kelo app target stays macOS-gated above. iOS/iPadOS get
    // their own app target from the xcodegen spec, linking KeloKit.
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: products,
    targets: targets
)
