import Foundation

// MARK: - Where Kelo's data lives
//
// One authoritative, platform-aware seam for the data directory every Store
// resolves against. This is also the single place iCloud sync will later plug
// in ([[project_life_app_sync]]) — swap `baseURL` for a ubiquity container and
// every store follows, because they ALL go through `Portfolio.dirURL`, which
// forwards here.
//
//   macOS  → ~/Documents/stock-tracker  (unchanged: existing data keeps working)
//   iOS /  → the app sandbox's Documents directory (the only writable home a
//   iPadOS   sandboxed app has); seeds ship in the bundle, not next to the JSON.

public enum KeloStorage {
    /// The directory Kelo reads/writes its JSON in, per platform.
    public static var baseURL: URL {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/stock-tracker")
        #else
        // Sandboxed platforms: the app's own Documents directory.
        let dir = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Resolve a seed/example file. On macOS it sits beside the JSON (the repo
    /// layout); on iOS the writable dir starts empty, so seeds are read from
    /// the app bundle instead. Returns nil when there's no seed to copy.
    public static func seedURL(_ name: String) -> URL? {
        let beside = baseURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        #if !os(macOS)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if let bundled = Bundle.main.url(forResource: base, withExtension: ext) {
            return bundled
        }
        #endif
        return nil
    }
}
