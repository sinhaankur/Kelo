import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device Foundation Model — the most private option, no server, no
/// network, no data leaving the device. Preferred for Kelo's assistant when the
/// OS/hardware supports it (iOS 26 / macOS 26 with Apple Intelligence on).
///
/// The whole thing is guarded so the app still builds + runs on the shipped
/// deployment targets (iOS 17 / macOS 13): `#if canImport` covers the compile,
/// `@available` + `isAvailable` cover the runtime. On anything older, or with
/// Apple Intelligence off, `isAvailable` is false and callers fall back to
/// Ollama (or, if the user opted in, the cloud).
public enum AppleFoundationModel {

    /// Whether the on-device Apple model can actually answer right now.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        return false
        #else
        return false
        #endif
    }

    /// A short human reason it isn't available (for the settings UI), or nil.
    public static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use the on-device model."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading — try again shortly."
            case .unavailable:
                return "The on-device model isn't available right now."
            }
        }
        return "Needs iOS 26 / macOS 26."
        #else
        return "Built without Apple Foundation Models."
        #endif
    }

    /// Ask the on-device model. Throws if it isn't available (callers should
    /// check `isAvailable` first and fall back).
    public static func analyze(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: system)
            let response = try await session.respond(to: user)
            return response.content
        }
        throw LlmError(message: "Apple Foundation Models needs iOS 26 / macOS 26.")
        #else
        throw LlmError(message: "This build has no Apple Foundation Models support.")
        #endif
    }
}
