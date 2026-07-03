import Foundation

/// Appearance follows the clock by default — light through the day,
/// dark in the evening/night — with a manual override.
public enum ThemeMode: String, CaseIterable {
    case auto, light, dark

    public static let lightStartHour = 7   // 07:00 local → light
    public static let darkStartHour = 19   // 19:00 local → dark

    public func isDark(at date: Date = Date()) -> Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            return hour < Self.lightStartHour || hour >= Self.darkStartHour
        }
    }

    public var label: String {
        switch self {
        case .auto: return "Auto (light 07–19)"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
