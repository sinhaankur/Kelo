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
            AgentService.stateURL,
        ]
        for url in files { hardenFile(at: url) }
    }

    /// Lock a single local file to owner-only (0600) — for stores that write
    /// their own cache (e.g. the Congress feed) outside the fixed list above.
    public static func hardenFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
