//
//  CatalogModels.swift
//  NuvioTV
//
//  Created by Claude Code
//  Swift data models for catalog browsing
//

import Foundation

// MARK: - Catalog Models

/// Catalog collection with items
struct NuvioCatalog: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let itemIds: [String]
    let contentType: String?
    let catalogId: String?

    init(
        id: String,
        name: String,
        description: String,
        itemIds: [String],
        contentType: String? = nil,
        catalogId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.itemIds = itemIds
        self.contentType = contentType
        self.catalogId = catalogId
    }
}

/// Content metadata
struct NuvioMeta: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let posterUrl: String?
    let backgroundUrl: String?
    let logoUrl: String?
    let imdbId: String?
    let tmdbId: Int?
    let type: String
    let year: Int?
    let genres: [String]?
    let rating: Double?
    let releaseInfo: String?
    let runtime: String?
    let cast: [String]?
    let director: [String]?
    let writer: [String]?
    let certification: String?
    let country: String?
    let released: String?
    /// Series release status from Cinemeta ("Ended", "Continuing"). nil for movies.
    let status: String?
    /// Series episodes (Stremio `videos`). nil/empty for movies.
    let videos: [NuvioVideo]?
    /// YouTube trailer ids from Cinemeta `trailers` / `trailerStreams`.
    let trailerYtIds: [String]?

    var isSeries: Bool { type == "series" }

    init(
        id: String,
        name: String,
        description: String?,
        posterUrl: String?,
        backgroundUrl: String?,
        logoUrl: String?,
        imdbId: String?,
        tmdbId: Int?,
        type: String,
        year: Int?,
        genres: [String]?,
        rating: Double?,
        releaseInfo: String?,
        runtime: String?,
        cast: [String]?,
        director: [String]?,
        writer: [String]?,
        certification: String?,
        country: String?,
        released: String?,
        status: String? = nil,
        videos: [NuvioVideo]? = nil,
        trailerYtIds: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.posterUrl = posterUrl
        self.backgroundUrl = backgroundUrl
        self.logoUrl = logoUrl
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.type = type
        self.year = year
        self.genres = genres
        self.rating = rating
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.cast = cast
        self.director = director
        self.writer = writer
        self.certification = certification
        self.country = country
        self.released = released
        self.status = status
        self.videos = videos
        self.trailerYtIds = trailerYtIds
    }
}

/// A single series episode (Stremio `videos[]`).
struct NuvioVideo: Identifiable, Codable, Hashable {
    let id: String          // e.g. "tt0903747:1:1"
    let title: String
    let season: Int
    let episode: Int
    let thumbnail: String?
    let overview: String?
    let released: String?
    let rating: String?
}

/// Video stream information
struct NuvioSubtitle: Identifiable, Codable, Equatable {
    var id: String { url }
    let url: String
    let language: String
    let label: String?
}

struct NuvioStream: Identifiable, Codable {
    var id: String { url ?? UUID().uuidString }
    let url: String?
    let name: String?
    let description: String?
    let addonName: String?
    let subtitles: [NuvioSubtitle]

    init(
        url: String?,
        name: String?,
        description: String?,
        addonName: String?,
        subtitles: [NuvioSubtitle] = []
    ) {
        self.url = url
        self.name = name
        self.description = description
        self.addonName = addonName
        self.subtitles = subtitles
    }
}

enum PlaybackMarkers {
    static let trailerSubtitle = "Trailer"
}

enum EpisodeTagResolver {
    static func episodeNumbers(in text: String) -> (season: Int, episode: Int)? {
        let patterns = [
            #"(?i)(?:^|[^A-Za-z0-9])S(\d{1,2})[\s._-]*E(\d{1,3})(?:[^A-Za-z0-9]|$)"#,
            #"(?i)(?:^|[^A-Za-z0-9])(\d{1,2})x(\d{1,3})(?:[^A-Za-z0-9]|$)"#,
            #"(?i)(?:season|s)[\s._-]*(\d{1,2})[\s._-]*(?:episode|ep|e)[\s._-]*(\d{1,3})"#,
            #"(?i)(?:^|[^A-Za-z0-9])tt\d+:(\d{1,2}):(\d{1,3})(?:[^A-Za-z0-9]|$)"#
        ]

        for pattern in patterns {
            guard let match = text.range(of: pattern, options: .regularExpression) else { continue }
            let numbers = text[match]
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }

            if numbers.count >= 2 {
                return (numbers[numbers.count - 2], numbers[numbers.count - 1])
            }
        }

        return nil
    }
}

struct TrailerPlaybackSource {
    let videoUrl: String
    let audioUrl: String?
}

struct ContinueWatchingItem: Identifiable, Codable {
    var id: String { meta.id }
    let meta: NuvioMeta
    let streamUrl: String
    let position: Double
    let duration: Double
    let lastWatchedAt: Date
    /// Which episode this progress belongs to (nil for movies and for entries
    /// saved before episode tracking existed — optionals keep old JSON decoding).
    let season: Int?
    let episode: Int?
    /// True when this entry is a fresh next-episode suggestion (the previous
    /// episode was finished) rather than real playback progress. Optional so
    /// old persisted JSON keeps decoding.
    let isUpNext: Bool?

    var isUpNextEntry: Bool { isUpNext == true }

    init(
        meta: NuvioMeta,
        streamUrl: String,
        position: Double,
        duration: Double,
        lastWatchedAt: Date,
        season: Int? = nil,
        episode: Int? = nil,
        isUpNext: Bool? = nil
    ) {
        self.meta = meta
        self.streamUrl = streamUrl
        self.position = position
        self.duration = duration
        self.lastWatchedAt = lastWatchedAt
        self.season = season
        self.episode = episode
        self.isUpNext = isUpNext
    }

    /// Episode numbers for display. Entries saved before episode tracking have
    /// nil season/episode; for those, fall back to a stream filename tag when
    /// possible, then to the first playable episode in stored series metadata.
    private var resolvedNumbers: (season: Int, episode: Int)? {
        if let season, let episode { return (season, episode) }
        guard meta.isSeries else { return nil }
        if let numbers = EpisodeTagResolver.episodeNumbers(in: streamUrl) {
            return numbers
        }
        return firstPlayableEpisode.map { ($0.season, $0.episode) }
    }

    var episodeNumbers: (season: Int, episode: Int)? {
        resolvedNumbers
    }

    private var firstPlayableEpisode: NuvioVideo? {
        guard let videos = meta.videos, !videos.isEmpty else { return nil }
        let sorted = videos.sorted {
            (seasonSortKey($0.season), $0.episode) < (seasonSortKey($1.season), $1.episode)
        }
        return sorted.first { $0.season > 0 } ?? sorted.first
    }

    private func seasonSortKey(_ season: Int) -> Int {
        season <= 0 ? Int.max : season
    }

    /// "S1 E3 · Title" line for the episode in progress; nil when unknown.
    var episodeDisplayLine: String? {
        guard let label = episodeLabel else { return nil }
        if let title = episodeVideo?.title, !title.isEmpty {
            return "\(label) · \(title)"
        }
        return label
    }

    /// "S1 E3" label for the episode in progress; nil when unknown.
    var episodeLabel: String? {
        guard let numbers = resolvedNumbers else { return nil }
        return "S\(numbers.season) E\(numbers.episode)"
    }

    /// The full episode entry from the stored series meta, carrying the
    /// episode's title and overview for display.
    var episodeVideo: NuvioVideo? {
        guard let numbers = resolvedNumbers else { return nil }
        return meta.videos?.first { $0.season == numbers.season && $0.episode == numbers.episode }
    }

    /// Player-style episode line ("S1 · E3 · Title"); nil when unknown.
    var episodeSubtitle: String? {
        guard let numbers = resolvedNumbers else { return nil }
        let title = episodeVideo?.title ?? "Episode \(numbers.episode)"
        return "S\(numbers.season) · E\(numbers.episode) · \(title)"
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var resumePosition: Double {
        max(0, min(position, max(duration - 5, 0)))
    }

    var remainingText: String {
        let remaining = max(0, duration - position)
        let minutes = Int(remaining / 60)
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainder)m left"
        }
        return "\(max(minutes, 1))m left"
    }
}

enum ContinueWatchingStore {
    /// Posted whenever the list changes (progress saved, item removed, profile
    /// switched) so views like Home can refresh their Continue Watching row
    /// without relying on `onAppear` — which no longer re-fires now that Home
    /// stays mounted behind the Details/Player overlays.
    static let changedNotification = Notification.Name("nuvio.tv.continueWatching.changed")

    /// Base key. Used on its own for the legacy (pre-profile) shared list and
    /// suffixed with the active profile id for per-profile watch history.
    private static let baseKey = "nuvio.tv.continueWatching.items"
    private static let maxItems = 20

    /// Identifier of the profile whose watch history is currently active.
    /// Set at launch and whenever the user switches profiles so each profile
    /// keeps its own Continue Watching list (app settings stay shared device-wide).
    private(set) static var activeProfileId: String?

    /// Point the store at a profile. Call on launch and on every profile switch
    /// so reads/writes land in that profile's bucket.
    static func setActiveProfile(_ profileId: String?) {
        activeProfileId = profileId
        migrateLegacyHistoryIfNeeded()
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static var storageKey: String {
        guard let id = activeProfileId, !id.isEmpty else { return baseKey }
        return "\(baseKey).\(id)"
    }

    static func items() -> [ContinueWatchingItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ContinueWatchingItem].self, from: data) else {
            return []
        }

        return decoded
            .filter { shouldKeep(position: $0.position, duration: $0.duration) }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
    }

    static func item(for metaId: String) -> ContinueWatchingItem? {
        items().first { $0.meta.id == metaId }
    }

    static func save(meta: NuvioMeta, streamUrl: String, position: Double, duration: Double, season: Int? = nil, episode: Int? = nil) {
        guard shouldKeep(position: position, duration: duration) else {
            remove(metaId: meta.id)
            return
        }

        // A save that doesn't know its episode (resume paths that only carry a
        // stream URL) must not erase the episode identity an earlier save recorded.
        let existing = item(for: meta.id)
        let item = ContinueWatchingItem(
            meta: meta,
            streamUrl: streamUrl,
            position: position,
            duration: duration,
            lastWatchedAt: Date(),
            season: season ?? existing?.season,
            episode: episode ?? existing?.episode
        )
        let updated = ([item] + items().filter { $0.meta.id != meta.id }).prefix(maxItems)
        persist(Array(updated))
    }

    static func remove(metaId: String) {
        persist(items().filter { $0.meta.id != metaId })
    }

    static func mergeRemote(_ remoteItems: [ContinueWatchingItem]) {
        guard !remoteItems.isEmpty else { return }
        var byId: [String: ContinueWatchingItem] = [:]
        // Remote items come second and win timestamp ties, so a re-pull can
        // refresh an entry's presentation (e.g. up-next state) even when the
        // underlying remote row hasn't moved.
        (items() + remoteItems).forEach { item in
            let existing = byId[item.meta.id]
            if existing == nil || item.lastWatchedAt >= existing!.lastWatchedAt {
                byId[item.meta.id] = item
            }
        }
        persist(Array(byId.values).sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(maxItems).map { $0 })
    }

    static func replaceAll(_ newItems: [ContinueWatchingItem]) {
        persist(Array(newItems.sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(maxItems)))
    }

    private static func shouldKeep(position: Double, duration: Double) -> Bool {
        // Any started playback counts (> 0), matching the phone app's rule —
        // a stricter threshold here hides items the phone still lists.
        guard duration >= 60, position > 0 else { return false }
        let remaining = duration - position
        return remaining >= 60 && (position / duration) < 0.92
    }

    private static func persist(_ items: [ContinueWatchingItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Deletes every profile's watch history (and the legacy shared list).
    /// Called on sign-out so the next user starts with no resume state.
    static func eraseAllProfiles() {
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(baseKey) }
            .forEach { defaults.removeObject(forKey: $0) }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// One-time copy of the old shared list into the active profile's bucket so
    /// existing users keep their Continue Watching when profiles arrive. Only the
    /// first profile that becomes active inherits it; afterwards the legacy key
    /// is cleared so other profiles start clean.
    private static func migrateLegacyHistoryIfNeeded() {
        guard let id = activeProfileId, !id.isEmpty else { return }
        let profileKey = "\(baseKey).\(id)"
        let defaults = UserDefaults.standard
        // Nothing to migrate, or this profile already has its own history.
        guard defaults.data(forKey: profileKey) == nil,
              let legacyData = defaults.data(forKey: baseKey) else { return }
        defaults.set(legacyData, forKey: profileKey)
        defaults.removeObject(forKey: baseKey)
    }
}

struct LibraryStoreItem: Identifiable, Codable {
    var id: String { meta.id }
    let meta: NuvioMeta
    let addedAt: Date

    var stremioMeta: StremioMeta {
        StremioMeta(
            id: meta.id,
            name: meta.name,
            contentType: meta.type,
            poster: meta.posterUrl,
            background: meta.backgroundUrl,
            logo: meta.logoUrl,
            description: meta.description,
            releaseInfo: meta.releaseInfo ?? meta.year.map(String.init),
            imdbRating: meta.rating.map { String(format: "%.1f", $0) },
            year: meta.year.map(Int32.init),
            genres: meta.genres,
            runtime: meta.runtime
        )
    }
}

enum LibraryStore {
    static let changedNotification = Notification.Name("nuvio.tv.library.changed")

    private static let baseKey = "nuvio.tv.library.items"
    private(set) static var activeProfileId: String?

    static func setActiveProfile(_ profileId: String?) {
        activeProfileId = profileId
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static var storageKey: String {
        guard let id = activeProfileId, !id.isEmpty else { return baseKey }
        return "\(baseKey).\(id)"
    }

    static func items() -> [LibraryStoreItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LibraryStoreItem].self, from: data) else {
            return []
        }

        return decoded.sorted { $0.addedAt > $1.addedAt }
    }

    static func contains(metaId: String, type: String) -> Bool {
        items().contains { $0.meta.id == metaId && $0.meta.type.caseInsensitiveCompare(type) == .orderedSame }
    }

    @discardableResult
    static func toggle(meta: NuvioMeta) -> Bool {
        if contains(metaId: meta.id, type: meta.type) {
            remove(metaId: meta.id, type: meta.type)
            return false
        }

        add(meta)
        return true
    }

    static func add(_ meta: NuvioMeta) {
        let item = LibraryStoreItem(meta: meta, addedAt: Date())
        let updated = [item] + items().filter {
            !($0.meta.id == meta.id && $0.meta.type.caseInsensitiveCompare(meta.type) == .orderedSame)
        }
        persist(updated)
    }

    static func remove(metaId: String, type: String) {
        persist(items().filter {
            !($0.meta.id == metaId && $0.meta.type.caseInsensitiveCompare(type) == .orderedSame)
        })
    }

    static func mergeRemote(_ remoteItems: [LibraryStoreItem]) {
        guard !remoteItems.isEmpty else { return }
        var byKey: [String: LibraryStoreItem] = [:]
        (items() + remoteItems).forEach { item in
            let key = "\(item.meta.type.lowercased()):\(item.meta.id)"
            let existing = byKey[key]
            if existing == nil || item.addedAt > existing!.addedAt {
                byKey[key] = item
            }
        }
        persist(Array(byKey.values).sorted { $0.addedAt > $1.addedAt })
    }

    static func replaceAll(_ newItems: [LibraryStoreItem]) {
        persist(newItems.sorted { $0.addedAt > $1.addedAt })
    }

    private static func persist(_ items: [LibraryStoreItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Deletes every profile's library (and the legacy shared one) on sign-out.
    static func eraseAllProfiles() {
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(baseKey) }
            .forEach { defaults.removeObject(forKey: $0) }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}

struct WatchedStoreItem: Identifiable, Codable {
    var id: String {
        if let season, let episode {
            return "\(meta.type):\(meta.id):s\(season)e\(episode)"
        }
        return "\(meta.type):\(meta.id)"
    }
    let meta: NuvioMeta
    let watchedAt: Date
    /// Which episode this entry marks; nil for movies and whole-title marks.
    let season: Int?
    let episode: Int?

    init(meta: NuvioMeta, watchedAt: Date, season: Int? = nil, episode: Int? = nil) {
        self.meta = meta
        self.watchedAt = watchedAt
        self.season = season
        self.episode = episode
    }
}

enum WatchedStore {
    static let changedNotification = Notification.Name("nuvio.tv.watched.changed")

    private static let baseKey = "nuvio.tv.watched.items"
    private(set) static var activeProfileId: String?

    static func setActiveProfile(_ profileId: String?) {
        activeProfileId = profileId
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static var storageKey: String {
        guard let id = activeProfileId, !id.isEmpty else { return baseKey }
        return "\(baseKey).\(id)"
    }

    static func items() -> [WatchedStoreItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WatchedStoreItem].self, from: data) else {
            return []
        }

        return decoded.sorted { $0.watchedAt > $1.watchedAt }
    }

    /// Whole-title watched state (movies, or a series marked watched
    /// explicitly). Episode-level entries deliberately don't count here so one
    /// finished episode doesn't checkmark the whole series poster.
    static func contains(metaId: String, type: String) -> Bool {
        items().contains {
            $0.meta.id == metaId
                && $0.meta.type.caseInsensitiveCompare(type) == .orderedSame
                && $0.season == nil && $0.episode == nil
        }
    }

    static func containsEpisode(metaId: String, season: Int, episode: Int) -> Bool {
        items().contains { $0.meta.id == metaId && $0.season == season && $0.episode == episode }
    }

    /// "season:episode" keys of every watched episode of a series, for the
    /// Details episode strip.
    static func watchedEpisodeKeys(metaId: String) -> Set<String> {
        Set(items().compactMap { item in
            guard item.meta.id == metaId, let season = item.season, let episode = item.episode else {
                return nil
            }
            return "\(season):\(episode)"
        })
    }

    @discardableResult
    static func toggle(meta: NuvioMeta) -> Bool {
        if contains(metaId: meta.id, type: meta.type) {
            remove(metaId: meta.id, type: meta.type)
            return false
        }

        markWatched(meta)
        return true
    }

    static func markWatched(_ meta: NuvioMeta, season: Int? = nil, episode: Int? = nil) {
        ContinueWatchingStore.remove(metaId: meta.id)
        let item = WatchedStoreItem(meta: meta, watchedAt: Date(), season: season, episode: episode)
        let updated = [item] + items().filter {
            !($0.meta.id == meta.id
                && $0.meta.type.caseInsensitiveCompare(meta.type) == .orderedSame
                && $0.season == season && $0.episode == episode)
        }
        clearTombstone(metaId: meta.id, season: season, episode: episode)
        persist(updated)
    }

    /// Removes the whole-title mark only; per-episode history stays. Leaves a
    /// tombstone so the next sync deletes the remote row instead of pulling the
    /// mark right back.
    static func remove(metaId: String, type: String) {
        addTombstone(metaId: metaId, season: nil, episode: nil)
        persist(items().filter {
            !($0.meta.id == metaId
                && $0.meta.type.caseInsensitiveCompare(type) == .orderedSame
                && $0.season == nil && $0.episode == nil)
        })
    }

    /// Merges a FULL remote snapshot. Tombstones (locally removed marks) block
    /// their remote row and stay alive until a pull shows the row is really
    /// gone from the server — the pushed delete is best-effort, so the pull is
    /// the confirmation. A newer re-watch on another device supersedes one.
    static func mergeRemote(_ remoteItems: [WatchedStoreItem]) {
        let removedMarks = tombstones()
        guard !remoteItems.isEmpty || !removedMarks.isEmpty else { return }

        let stillBlocking = removedMarks.filter { tombstone in
            remoteItems.contains {
                $0.meta.id == tombstone.metaId && $0.season == tombstone.season
                    && $0.episode == tombstone.episode && $0.watchedAt <= tombstone.removedAt
            }
        }
        if stillBlocking.count != removedMarks.count {
            persistTombstones(stillBlocking)
        }

        let accepted = remoteItems.filter { item in
            !stillBlocking.contains {
                $0.metaId == item.meta.id && $0.season == item.season && $0.episode == item.episode
            }
        }

        var byKey: [String: WatchedStoreItem] = [:]
        (items() + accepted).forEach { item in
            let key = item.id.lowercased()
            let existing = byKey[key]
            if existing == nil || item.watchedAt > existing!.watchedAt {
                byKey[key] = item
            }
        }
        persist(Array(byKey.values).sorted { $0.watchedAt > $1.watchedAt })
    }

    // MARK: Tombstones — locally deleted marks awaiting remote deletion

    struct Tombstone: Codable, Equatable {
        let metaId: String
        let season: Int?
        let episode: Int?
        let removedAt: Date
    }

    private static var tombstoneStorageKey: String {
        guard let id = activeProfileId, !id.isEmpty else { return "\(baseKey).tombstones" }
        return "\(baseKey).tombstones.\(id)"
    }

    static func tombstones() -> [Tombstone] {
        guard let data = UserDefaults.standard.data(forKey: tombstoneStorageKey),
              let decoded = try? JSONDecoder().decode([Tombstone].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func addTombstone(metaId: String, season: Int?, episode: Int?) {
        let entry = Tombstone(metaId: metaId, season: season, episode: episode, removedAt: Date())
        let updated = tombstones().filter {
            !($0.metaId == metaId && $0.season == season && $0.episode == episode)
        } + [entry]
        persistTombstones(updated)
    }

    private static func clearTombstone(metaId: String, season: Int?, episode: Int?) {
        persistTombstones(tombstones().filter {
            !($0.metaId == metaId && $0.season == season && $0.episode == episode)
        })
    }

    /// Called after the remote rows were deleted successfully.
    static func clearTombstones(_ cleared: [Tombstone]) {
        persistTombstones(tombstones().filter { !cleared.contains($0) })
    }

    private static func persistTombstones(_ entries: [Tombstone]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: tombstoneStorageKey)
    }

    static func replaceAll(_ newItems: [WatchedStoreItem]) {
        persist(newItems.sorted { $0.watchedAt > $1.watchedAt })
    }

    private static func persist(_ items: [WatchedStoreItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Deletes every profile's watched marks and tombstones (the tombstone keys
    /// share `baseKey` as their prefix) on sign-out.
    static func eraseAllProfiles() {
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(baseKey) }
            .forEach { defaults.removeObject(forKey: $0) }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}

// MARK: - Per-profile settings

/// Backs every app setting with a per-profile `UserDefaults` suite so changing
/// the theme (or any other preference) on one profile never affects another.
///
/// SwiftUI views read it through `.defaultAppStorage(ProfileSettings.store(for:))`
/// so the 100-odd `@AppStorage` sites need no changes; the few direct
/// `UserDefaults` reads (subtitle style/language, reset) use `.current`.
///
/// A new profile is seeded with a copy of the active profile's settings at
/// creation, then diverges independently. Existing installs whose settings live
/// in `.standard` migrate that snapshot into each profile the first time it is
/// used, so nobody loses their preferences when profiles arrive.
enum ProfileSettings {
    private static let suitePrefix = "nuvio.tv.profile.settings"
    private static let seededFlag = "nuvio.tv.profile.settings.seeded"

    /// Settings store for the active profile. `.standard` until one is loaded
    /// (e.g. on the login / "Who's watching?" screens).
    private(set) static var current: UserDefaults = .standard

    /// The suite backing a given profile id, or `.standard` when there is none.
    /// `UserDefaults(suiteName:)` returns the same shared store for a name, so
    /// repeated calls for one profile all read and write the same values.
    static func store(for profileId: String?) -> UserDefaults {
        guard let id = profileId, !id.isEmpty,
              let suite = UserDefaults(suiteName: "\(suitePrefix).\(id)") else {
            return .standard
        }
        return suite
    }

    /// Point reads/writes at a profile. Called on launch and on every switch.
    /// Seeds the profile from the pre-profile global settings the first time it
    /// is used so existing installs keep their preferences.
    static func setActiveProfile(_ profileId: String?) {
        guard let id = profileId, !id.isEmpty else { return }
        let suite = store(for: id)
        seedFromGlobalIfNeeded(suite)
        current = suite
    }

    static func clearActiveProfile() {
        current = .standard
    }

    /// Deletes the given profiles' settings suites and the pre-profile copies
    /// in `.standard`, so sign-out leaves no add-ons, API keys, or preferences
    /// behind. Points `current` back at `.standard` first so nothing keeps
    /// writing into a removed suite.
    static func eraseAll(profileIds: [String]) {
        current = .standard
        for id in Set(profileIds) where !id.isEmpty {
            UserDefaults.standard.removePersistentDomain(forName: "\(suitePrefix).\(id)")
        }
        for key in SettingsKey.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Clone the current profile's settings into a freshly created profile, then
    /// mark it seeded so the global migration never overwrites the copy.
    static func seedNewProfile(_ profileId: String, copyingFrom source: UserDefaults? = nil) {
        let destination = store(for: profileId)
        copySettings(from: source ?? current, to: destination)
        destination.set(true, forKey: seededFlag)
    }

    private static func seedFromGlobalIfNeeded(_ suite: UserDefaults) {
        guard !suite.bool(forKey: seededFlag) else { return }
        copySettings(from: .standard, to: suite)
        suite.set(true, forKey: seededFlag)
    }

    private static func copySettings(from source: UserDefaults, to destination: UserDefaults) {
        guard source != destination else { return }
        for key in SettingsKey.all {
            if let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
            } else {
                destination.removeObject(forKey: key)
            }
        }
    }
}

/// Paginated catalog page
struct CatalogPage {
    let items: [NuvioMeta]
    let hasMore: Bool
    let page: Int
    let nextSkip: Int?

    init(
        items: [NuvioMeta],
        hasMore: Bool,
        page: Int,
        nextSkip: Int? = nil
    ) {
        self.items = items
        self.hasMore = hasMore
        self.page = page
        self.nextSkip = nextSkip
    }
}

// MARK: - Filter & Sort Models

/// Filter state for catalog browsing
struct FilterState: Equatable {
    var contentType: String = "movie"
    var genre: String? = nil
    var year: Int? = nil
    var sort: SortOption = .trending
}

/// Sort options for catalog
enum SortOption: String, CaseIterable {
    case trending = "top"
    case popular = "popular"
    case newest = "newest"
    case rating = "rating"

    var displayName: String {
        switch self {
        case .trending: return "Trending"
        case .popular: return "Popular"
        case .newest: return "Newest"
        case .rating: return "Top Rated"
        }
    }

    var catalogId: String {
        return self.rawValue
    }
}

// MARK: - UI State

/// UI state for catalog browse screen
struct CatalogBrowseUiState {
    var isLoading: Bool = false
    var items: [NuvioMeta] = []
    var currentPage: Int = 1
    var hasMore: Bool = true
    var filterState: FilterState = FilterState()
    var availableGenres: [String] = []
    var error: String? = nil
    var isLoadingMore: Bool = false
}

/// UI state for details screen
struct DetailsUiState {
    var isLoading: Bool = true
    var meta: NuvioMeta? = nil
    var streams: [NuvioStream] = []
    var isLoadingStreams: Bool = false
    var error: String? = nil
    var isInWatchlist: Bool = false
    var isWatched: Bool = false
    var userRating: Int? = nil
}
