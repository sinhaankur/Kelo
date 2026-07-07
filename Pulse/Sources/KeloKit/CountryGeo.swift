import Foundation

/// Country name → approximate centroid (lat, lon), for plotting GDELT events
/// on the tactical map. Covers the countries that dominate conflict and
/// market news; unknown names return nil (the event still lists, just
/// without a pin). GDELT uses full English country names.
public enum CountryGeo {
    static let centers: [String: (lat: Double, lon: Double)] = [
        "United States": (39.8, -98.6), "Canada": (56.1, -106.3),
        "Mexico": (23.6, -102.6), "Brazil": (-14.2, -51.9),
        "Argentina": (-38.4, -63.6), "United Kingdom": (55.4, -3.4),
        "France": (46.6, 2.2), "Germany": (51.2, 10.4), "Italy": (41.9, 12.6),
        "Spain": (40.5, -3.7), "Ukraine": (48.4, 31.2), "Russia": (61.5, 105.3),
        "Poland": (51.9, 19.1), "Netherlands": (52.1, 5.3), "Switzerland": (46.8, 8.2),
        "Sweden": (60.1, 18.6), "Norway": (60.5, 8.5), "Turkey": (38.9, 35.2),
        "Israel": (31.0, 34.9), "Palestine": (31.9, 35.2), "Iran": (32.4, 53.7),
        "Iraq": (33.2, 43.7), "Saudi Arabia": (23.9, 45.1), "Syria": (34.8, 39.0),
        "Lebanon": (33.9, 35.9), "Yemen": (15.6, 48.0), "Egypt": (26.8, 30.8),
        "United Arab Emirates": (23.4, 53.8), "Qatar": (25.4, 51.2),
        "India": (20.6, 79.0), "Pakistan": (30.4, 69.3), "China": (35.9, 104.2),
        "Japan": (36.2, 138.3), "South Korea": (35.9, 127.8),
        "North Korea": (40.3, 127.5), "Taiwan": (23.7, 121.0),
        "Hong Kong": (22.3, 114.2), "Vietnam": (14.1, 108.3),
        "Thailand": (15.9, 100.9), "Indonesia": (-0.8, 113.9),
        "Philippines": (12.9, 121.8), "Malaysia": (4.2, 101.9),
        "Australia": (-25.3, 133.8), "New Zealand": (-40.9, 174.9),
        "South Africa": (-30.6, 22.9), "Nigeria": (9.1, 8.7),
        "Ethiopia": (9.1, 40.5), "Kenya": (-0.0, 37.9), "Sudan": (12.9, 30.2),
        "Libya": (26.3, 17.2), "Algeria": (28.0, 1.7), "Morocco": (31.8, -7.1),
        "Venezuela": (6.4, -66.6), "Colombia": (4.6, -74.3), "Chile": (-35.7, -71.5),
        "Peru": (-9.2, -75.0), "Afghanistan": (33.9, 67.7), "Greece": (39.1, 21.8),
        "Belgium": (50.5, 4.5), "Ireland": (53.4, -8.2), "Portugal": (39.4, -8.2),
        "Austria": (47.5, 14.6), "Singapore": (1.35, 103.8),
    ]

    public static func center(_ country: String) -> (lat: Double, lon: Double)? {
        centers[country]
    }
}
