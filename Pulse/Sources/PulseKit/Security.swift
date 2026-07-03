import Foundation

/// Security posture: everything sensitive lives in local files that never
/// enter git — this locks their POSIX permissions to owner-only (0600) on
/// every launch, on macOS and Linux alike.
public enum Security {
    public static func hardenDataFiles() {
        let files = [
            Portfolio.fileURL,
            AppConfig.fileURL,
            SnapshotStore.fileURL,
            PaperLedger.fileURL,
            Watchlist.fileURL,
        ]
        for url in files where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
