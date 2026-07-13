import XCTest
@testable import KeloKit

/// The Apple on-device model is availability-gated (iOS 26 / macOS 26 + Apple
/// Intelligence). These prove the FALLBACK contract holds: when it can't run,
/// `isAvailable` is false and there's an honest reason — so callers fall back
/// to Ollama / the local answer instead of breaking.
final class AppleFoundationModelTests: XCTestCase {

    func testAvailabilityAndReasonAreConsistent() {
        // On the CI/test host the model won't be usable → available == false and
        // a reason is present; if a future host DOES have it, reason is nil.
        if AppleFoundationModel.isAvailable {
            XCTAssertNil(AppleFoundationModel.unavailableReason)
        } else {
            XCTAssertNotNil(AppleFoundationModel.unavailableReason)
            XCTAssertFalse(AppleFoundationModel.unavailableReason!.isEmpty)
        }
    }

    func testAnalyzeThrowsWhenUnavailable() async {
        guard !AppleFoundationModel.isAvailable else { return } // skip where it works
        do {
            _ = try await AppleFoundationModel.analyze(system: "s", user: "u")
            XCTFail("should throw when the on-device model isn't available")
        } catch {
            // expected — callers catch this and fall back
        }
    }
}
