import SwiftUI

/// Add-on catalog/stream source. The management UI lives in
/// Settings → Integrations → Add-ons (see `AddonsSettingsSection`).
struct AddonItem: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let version: String
    let logoSystemName: String
    let isOfficial: Bool
    var isInstalled: Bool

    /// Core sources that cannot be removed.
    var isLocked: Bool { id == "cinemeta" || id == "opensubtitles-v3" }

    static let defaults: [AddonItem] = [
        AddonItem(id: "cinemeta", name: "Cinemeta", description: "Official Stremio metadata catalog provider for movies and series.", version: "3.0.4", logoSystemName: "film.fill", isOfficial: true, isInstalled: true),
        AddonItem(id: "opensubtitles-v3", name: "OpenSubtitles v3", description: "Official Stremio subtitle provider for movies and series.", version: "1.0.0", logoSystemName: "captions.bubble.fill", isOfficial: true, isInstalled: true),
        AddonItem(id: "local", name: "Local Files", description: "Import and stream videos from your local device storage or NAS.", version: "1.0.0", logoSystemName: "folder.fill", isOfficial: true, isInstalled: true),
        AddonItem(id: "torrentio", name: "Torrentio", description: "Provides streams from torrents of public providers like YTS, EZTV, and others.", version: "1.2.0", logoSystemName: "play.tv.fill", isOfficial: false, isInstalled: false),
        AddonItem(id: "youtube", name: "YouTube", description: "Watch official trailers and free YouTube channels directly inside Nuvio.", version: "2.1.0", logoSystemName: "video.fill", isOfficial: false, isInstalled: true),
        AddonItem(id: "twitch", name: "Twitch", description: "Live streams and recordings from popular gaming channels.", version: "0.9.0", logoSystemName: "gamecontroller.fill", isOfficial: false, isInstalled: false)
    ]
}
