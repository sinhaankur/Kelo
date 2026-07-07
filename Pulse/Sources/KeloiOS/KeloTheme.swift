import SwiftUI
import PulseKit

// Turns the shared KeloBrand tokens into SwiftUI Color/Font, matching
// sinhaankur.com. Fonts fall back to close system equivalents until the real
// Google fonts (Inter / Fraunces / JetBrains Mono — all free) are bundled into
// the app target, so the look is right now and exact later.

extension Color {
    init(_ rgb: KeloBrand.RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    static let keloPaper   = Color(KeloBrand.paper)
    static let keloInk     = Color(KeloBrand.ink)
    static let keloMuted   = Color(KeloBrand.inkMuted)
    static let keloAccent  = Color(KeloBrand.accent)
    static let keloDarkBg  = Color(KeloBrand.inkDarkBg)
    static let keloGood    = Color(KeloBrand.good)
    static let keloWarn    = Color(KeloBrand.warn)
    static let keloBad     = Color(KeloBrand.bad)
}

enum KeloFont {
    /// Editorial display (Fraunces) — headlines. Falls back to a serif.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        custom(KeloBrand.Font.display, size: size, fallback: .serif).weight(weight)
    }
    /// Body (Inter) — falls back to the system sans.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        custom(KeloBrand.Font.body, size: size, fallback: .default).weight(weight)
    }
    /// Mono (JetBrains Mono) — eyebrows / labels. Falls back to monospaced.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        custom(KeloBrand.Font.mono, size: size, fallback: .monospaced).weight(weight)
    }

    private static func custom(_ name: String, size: CGFloat, fallback: Font.Design) -> Font {
        // If the font isn't installed, `.custom` silently uses the system font;
        // pair it with the right design so the fallback still feels right.
        #if canImport(UIKit)
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        #endif
        return .system(size: size, design: fallback)
    }
}

/// An eyebrow label in the site's voice — mono, tracked, muted. Used above
/// every section, exactly like the "01 — DISCIPLINE" eyebrows on the site.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(KeloFont.mono(10, .semibold))
            .tracking(2)
            .foregroundStyle(Color.keloMuted)
    }
}
