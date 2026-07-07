import Foundation

// MARK: - Kelo brand tokens
//
// Kelo wears the same identity as sinhaankur.com — the editorial, warm-paper
// look Ankur already likes — so it reads as HIS product, not a stock app.
// Pulled straight from the site's design system (app/globals.css + layout.tsx):
//
//   background  #f5f5f0  warm off-white ("paper")
//   foreground  #0a0a0a  deep ink
//   accent      #cf9a2c  warm amber-gold (from the universe-engine palette)
//   dark bg     #0a0a0a  near-black, off-white text
//   type        Inter (body) · Fraunces (editorial display) · JetBrains Mono
//               (eyebrows / mono labels)
//
// This is the platform-agnostic source of truth (plain RGB + font names); the
// SwiftUI layer (KeloTheme) turns these into Color/Font. Keep values in sync
// with the website so the two never drift.

public enum KeloBrand {
    // Colours as sRGB 0–1 triples (r, g, b) so KeloKit stays UI-framework-free.
    public typealias RGB = (r: Double, g: Double, b: Double)

    // Light ("paper")
    public static let paper: RGB       = (0.961, 0.961, 0.941)  // #f5f5f0
    public static let ink: RGB         = (0.039, 0.039, 0.039)  // #0a0a0a
    public static let inkMuted: RGB    = (0.42,  0.42,  0.42)   // muted-foreground
    public static let inkDim: RGB      = (0.55,  0.55,  0.55)   // dimmer captions

    // Accent — warm amber-gold, one system across both themes.
    public static let accent: RGB      = (0.812, 0.604, 0.173)  // ~#cf9a2c

    // Dark
    public static let inkDarkBg: RGB   = (0.086, 0.086, 0.086)  // #161616-ish
    public static let paperOnDark: RGB = (0.965, 0.965, 0.965)  // off-white text

    // Semantic status — kept close to the site's greens/reds but a touch warm.
    public static let good: RGB        = (0.36, 0.60, 0.36)
    public static let warn: RGB        = (0.81, 0.60, 0.17)     // reuse accent family
    public static let bad: RGB         = (0.78, 0.30, 0.26)

    // Font family names (the app bundles/loads these; see KeloTheme).
    public enum Font {
        public static let body     = "Inter"
        public static let display  = "Fraunces"
        public static let serif    = "Instrument Serif"
        public static let mono     = "JetBrains Mono"
    }

    public static let displayName = "Kelo"
    public static let tagline     = "Health and Wealth"
}
