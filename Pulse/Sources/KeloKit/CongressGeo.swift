import Foundation

/// Approximate centre coordinate for each US state — so a member's disclosed
/// trades can be plotted on the map by the state they represent (from the
/// feed's 2-letter `state`). Mirrors `CountryGeo`: a plain lookup table, no
/// network, unit-tested for coverage. Coordinates are state geographic centres
/// (good enough to place a marker; the map isn't a survey instrument).
public enum CongressGeo {
    /// (lat, lon) by USPS 2-letter state/territory code.
    public static let centers: [String: (lat: Double, lon: Double)] = [
        "AL": (32.8, -86.8), "AK": (64.2, -149.5), "AZ": (34.3, -111.7),
        "AR": (34.9, -92.4), "CA": (37.2, -119.4), "CO": (39.0, -105.5),
        "CT": (41.6, -72.7), "DE": (39.0, -75.5), "FL": (28.6, -82.4),
        "GA": (32.6, -83.4), "HI": (20.3, -156.4), "ID": (44.4, -114.6),
        "IL": (40.0, -89.2), "IN": (39.9, -86.3), "IA": (42.0, -93.5),
        "KS": (38.5, -98.4), "KY": (37.5, -85.3), "LA": (31.0, -92.0),
        "ME": (45.4, -69.2), "MD": (39.0, -76.8), "MA": (42.3, -71.8),
        "MI": (44.3, -85.4), "MN": (46.3, -94.3), "MS": (32.7, -89.7),
        "MO": (38.4, -92.5), "MT": (47.0, -109.6), "NE": (41.5, -99.8),
        "NV": (39.3, -116.6), "NH": (43.7, -71.6), "NJ": (40.1, -74.7),
        "NM": (34.4, -106.1), "NY": (42.9, -75.6), "NC": (35.5, -79.4),
        "ND": (47.5, -100.3), "OH": (40.3, -82.8), "OK": (35.6, -97.5),
        "OR": (43.9, -120.6), "PA": (40.9, -77.8), "RI": (41.7, -71.5),
        "SC": (33.9, -80.9), "SD": (44.4, -100.2), "TN": (35.9, -86.4),
        "TX": (31.5, -99.3), "UT": (39.3, -111.7), "VT": (44.1, -72.7),
        "VA": (37.5, -78.9), "WA": (47.4, -120.5), "WV": (38.6, -80.6),
        "WI": (44.6, -90.0), "WY": (43.0, -107.6),
        // Non-state jurisdictions that appear in disclosures.
        "DC": (38.9, -77.0), "PR": (18.2, -66.4), "GU": (13.4, 144.8),
        "VI": (18.3, -64.9), "AS": (-14.3, -170.7), "MP": (15.2, 145.8),
    ]

    /// Centre for a state code (case-insensitive), or nil if unknown — never a
    /// guessed coordinate.
    public static func center(_ state: String?) -> (lat: Double, lon: Double)? {
        guard let s = state?.trimmingCharacters(in: .whitespaces).uppercased(), !s.isEmpty
        else { return nil }
        return centers[s]
    }
}
