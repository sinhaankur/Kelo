import Foundation

/// Single source of truth for branding — build-app.sh greps the version
/// from this file so the app bundle can never drift from the code again.
public enum PulseInfo {
    public static let name = "Pulse"
    public static let version = "0.7.2"
    public static let tagline = "private, on-device portfolio tracker"
}
