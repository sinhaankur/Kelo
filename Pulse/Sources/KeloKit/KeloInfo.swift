import Foundation

/// Single source of truth for branding — build-app.sh greps the name and
/// version from this file so the app bundle can never drift from the code.
/// (Kelo grew out of the "Pulse" portfolio tracker; the internal SwiftPM
/// module/type names stay `Pulse*` — invisible to the user — while every
/// user-facing string reads Kelo.)
public enum KeloInfo {
    public static let name = "Kelo"
    public static let version = "0.27.0"
    public static let tagline = "private, on-device — your body and your money in one place"
    public static let author = "Built by sinhaankur"
    public static let repo = "https://github.com/sinhaankur/kelo"
}
