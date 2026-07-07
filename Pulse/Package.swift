// swift-tools-version: 5.9
import PackageDescription
import Foundation

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

// The macOS SwiftUI app target (AppKit sources) is only added when building
// the desktop app via SwiftPM. The iOS/iPadOS Xcode project (xcodegen) consumes
// this package purely for the KeloKit library, so it must NOT see this target —
// otherwise its AppKit sources fail to resolve for iOS. build-app.sh sets
// KELO_MACOS_APP=1; the iOS build doesn't, so the target is excluded there.
#if os(macOS)
if ProcessInfo.processInfo.environment["KELO_MACOS_APP"] == "1" {
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
}
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
