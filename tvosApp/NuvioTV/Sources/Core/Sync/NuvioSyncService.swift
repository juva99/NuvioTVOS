//
//  NuvioSyncService.swift
//  NuvioTV
//
//  Supabase-backed profile, settings, library, watched, and progress sync for
//  tvOS. Mirrors the Android TV app's RPC contract without adding the Supabase
//  SDK to this target.
//

import Combine
import Foundation

@MainActor
final class NuvioSyncManager: ObservableObject {
    private let client = SupabaseSyncClient()

    private weak var authManager: AuthManager?
    private weak var profileViewModel: ProfileViewModel?
    private var observers: [NSObjectProtocol] = []
    private var pullTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var completedInitialPullKeys: Set<String> = []
    private var isApplyingRemote = false
    private var didAttach = false

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(authManager: AuthManager, profileViewModel: ProfileViewModel) {
        guard !didAttach else { return }
        didAttach = true
        self.authManager = authManager
        self.profileViewModel = profileViewModel

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProfileManager.profilesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        })
        observers.append(center.addObserver(
            forName: LibraryStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        })
        observers.append(center.addObserver(
            forName: WatchedStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        })
        observers.append(center.addObserver(
            forName: ContinueWatchingStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        })
    }

    func authStateChanged(_ state: AuthState) {
        switch state {
        case .fullAccount:
            schedulePull(force: true)
        case .signedOut:
            pullTask?.cancel()
            pushTask?.cancel()
            completedInitialPullKeys.removeAll()
        case .loading:
            break
        }
    }

    func activeProfileChanged(_ profile: Profile?) {
        guard profile != nil, !isApplyingRemote else { return }
        schedulePull(force: true)
    }

    private func schedulePull(force: Bool = false) {
        guard AuthConfig.isConfigured else { return }
        guard authManager?.isAuthenticated == true else { return }
        if !force, pullTask?.isCancelled == false { return }

        pullTask?.cancel()
        pullTask = Task { @MainActor [weak self] in
            if !force {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            await self?.pullThenPush()
        }
    }

    private func schedulePush() {
        guard !isApplyingRemote else { return }
        guard AuthConfig.isConfigured else { return }
        guard authManager?.isAuthenticated == true else { return }
        guard let key = currentSyncKey(), completedInitialPullKeys.contains(key) else { return }

        pushTask?.cancel()
        pushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.pushLocalSnapshots()
        }
    }

    private func pullThenPush() async {
        guard let authManager, let profileViewModel else { return }
        guard let session = await authManager.validSessionForSync() else { return }

        do {
            let remoteProfiles = try await client.pullProfiles(session: session)
            if !remoteProfiles.isEmpty {
                let merged = ProfileSyncIndexStore.localProfiles(
                    from: remoteProfiles,
                    preserving: profileViewModel.profiles
                )
                isApplyingRemote = true
                profileViewModel.applyRemoteProfiles(merged)
                isApplyingRemote = false
            } else if !profileViewModel.profiles.isEmpty {
                try await client.pushProfiles(
                    session: session,
                    profiles: profileViewModel.profiles
                )
            }

            guard let activeProfile = profileViewModel.activeProfile ?? profileViewModel.profiles.first else {
                return
            }

            let remoteProfileId = ProfileSyncIndexStore.remoteId(
                for: activeProfile,
                in: profileViewModel.profiles
            )

            isApplyingRemote = true
            let settingsApplied = try await client.pullProfileSettings(
                session: session,
                remoteProfileId: remoteProfileId,
                localProfileId: activeProfile.id
            )
            if !settingsApplied {
                try await client.pushProfileSettings(
                    session: session,
                    remoteProfileId: remoteProfileId,
                    localProfileId: activeProfile.id
                )
            }

            if Self.watchStateSyncEnabled(for: activeProfile.id) {
                let remoteLibrary = try await client.pullLibrary(
                    session: session,
                    remoteProfileId: remoteProfileId
                )
                LibraryStore.mergeRemote(remoteLibrary)

                let remoteWatched = try await client.pullWatched(
                    session: session,
                    remoteProfileId: remoteProfileId
                )
                WatchedStore.mergeRemote(remoteWatched)

                let remoteProgress = try await client.pullWatchProgress(
                    session: session,
                    remoteProfileId: remoteProfileId
                )
                ContinueWatchingStore.mergeRemote(remoteProgress)
            }
            isApplyingRemote = false

            if let key = currentSyncKey() {
                completedInitialPullKeys.insert(key)
            }
            await pushLocalSnapshots()
        } catch {
            isApplyingRemote = false
            print("Nuvio sync failed: \(error.localizedDescription)")
        }
    }

    private func pushLocalSnapshots() async {
        guard let authManager, let profileViewModel else { return }
        guard let session = await authManager.validSessionForSync() else { return }
        guard let activeProfile = profileViewModel.activeProfile ?? profileViewModel.profiles.first else { return }

        let remoteProfileId = ProfileSyncIndexStore.remoteId(
            for: activeProfile,
            in: profileViewModel.profiles
        )

        do {
            try await client.pushProfiles(session: session, profiles: profileViewModel.profiles)
            try await client.pushProfileSettings(
                session: session,
                remoteProfileId: remoteProfileId,
                localProfileId: activeProfile.id
            )

            guard Self.watchStateSyncEnabled(for: activeProfile.id) else { return }
            try await client.pushLibrary(session: session, remoteProfileId: remoteProfileId)
            try await client.pushWatched(session: session, remoteProfileId: remoteProfileId)
            try await client.pushWatchProgress(session: session, remoteProfileId: remoteProfileId)
        } catch {
            print("Nuvio sync push failed: \(error.localizedDescription)")
        }
    }

    private func currentSyncKey() -> String? {
        guard let authManager, let profileViewModel else { return nil }
        guard case let .fullAccount(userId, _) = authManager.authState else { return nil }
        guard let activeProfile = profileViewModel.activeProfile ?? profileViewModel.profiles.first else {
            return nil
        }
        let remoteProfileId = ProfileSyncIndexStore.remoteId(
            for: activeProfile,
            in: profileViewModel.profiles
        )
        return "\(userId):\(remoteProfileId)"
    }

    private static func watchStateSyncEnabled(for profileId: String) -> Bool {
        let defaults = ProfileSettings.store(for: profileId)
        if let value = defaults.object(forKey: SettingsKey.accountSyncWatchState) as? Bool {
            return value
        }
        return true
    }
}

private enum ProfileSyncIndexStore {
    private static let prefix = "nuvio.tv.sync.profileIndex."

    static func remoteId(for profile: Profile, in profiles: [Profile]) -> Int {
        if let numeric = Int(profile.id), (1...6).contains(numeric) {
            bind(localId: profile.id, remoteId: numeric)
            return numeric
        }

        let key = prefix + profile.id
        let stored = UserDefaults.standard.integer(forKey: key)
        if (1...6).contains(stored) {
            return stored
        }

        let used = Set(profiles.compactMap { candidate -> Int? in
            if candidate.id == profile.id { return nil }
            if let numeric = Int(candidate.id), (1...6).contains(numeric) { return numeric }
            let mapped = UserDefaults.standard.integer(forKey: prefix + candidate.id)
            return (1...6).contains(mapped) ? mapped : nil
        })
        let assigned = (1...6).first(where: { !used.contains($0) }) ?? 1
        bind(localId: profile.id, remoteId: assigned)
        return assigned
    }

    static func localProfiles(from remoteProfiles: [RemoteProfile], preserving localProfiles: [Profile]) -> [Profile] {
        var localByRemoteId: [Int: Profile] = [:]
        localProfiles.forEach { profile in
            let remoteId: Int
            if let numeric = Int(profile.id), (1...6).contains(numeric) {
                remoteId = numeric
            } else {
                let mapped = UserDefaults.standard.integer(forKey: prefix + profile.id)
                guard (1...6).contains(mapped) else { return }
                remoteId = mapped
            }
            localByRemoteId[remoteId] = localByRemoteId[remoteId] ?? profile
        }

        return remoteProfiles
            .sorted { $0.profileIndex < $1.profileIndex }
            .map { remote in
                let localId = localByRemoteId[remote.profileIndex]?.id ?? String(remote.profileIndex)
                bind(localId: localId, remoteId: remote.profileIndex)
                return Profile(
                    id: localId,
                    name: remote.name.isEmpty ? "Nuvio User" : remote.name,
                    isPinProtected: false,
                    isAdmin: remote.profileIndex == 1,
                    avatarId: remote.avatarId?.isEmpty == false ? remote.avatarId! : "default"
                )
            }
    }

    private static func bind(localId: String, remoteId: Int) {
        UserDefaults.standard.set(remoteId, forKey: prefix + localId)
    }
}

fileprivate final class SupabaseSyncClient {
    private static let pullPageSize = 500
    private static let settingsPlatform = "tvos"
    private static let settingsFeature = "tvos_settings"

    private let session: URLSession = .shared
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let catalogRepository: CatalogRepository = CinemetaCatalogRepository()

    func pullProfiles(session: AuthSession) async throws -> [RemoteProfile] {
        try await rpc("sync_pull_profiles", session: session, params: [:])
    }

    func pushProfiles(session: AuthSession, profiles: [Profile]) async throws {
        let payloads = profiles.prefix(6).map { profile -> [String: Any] in
            [
                "profile_index": ProfileSyncIndexStore.remoteId(for: profile, in: profiles),
                "name": profile.name,
                "avatar_color_hex": "#1E88E5",
                "uses_primary_addons": false,
                "uses_primary_plugins": false,
                "avatar_id": profile.avatarId,
                "avatar_url": NSNull()
            ]
        }
        try await rpcVoid(
            "sync_push_profiles",
            session: session,
            params: [
                "p_client_max_profiles": 6,
                "p_profiles": payloads
            ]
        )
    }

    func pullProfileSettings(
        session: AuthSession,
        remoteProfileId: Int,
        localProfileId: String
    ) async throws -> Bool {
        let raw = try await rpcJSONObject(
            "sync_pull_profile_settings_blob",
            session: session,
            params: [
                "p_profile_id": remoteProfileId,
                "p_platform": Self.settingsPlatform
            ]
        )
        guard let rows = raw as? [[String: Any]],
              let settingsJSON = rows.first?["settings_json"] as? [String: Any],
              let features = settingsJSON["features"] as? [String: Any],
              let feature = features[Self.settingsFeature] as? [String: Any] else {
            return false
        }

        importSettings(feature, localProfileId: localProfileId)
        return true
    }

    func pushProfileSettings(
        session: AuthSession,
        remoteProfileId: Int,
        localProfileId: String
    ) async throws {
        let settingsJSON: [String: Any] = [
            "version": 1,
            "features": [
                Self.settingsFeature: exportSettings(localProfileId: localProfileId)
            ]
        ]
        try await rpcVoid(
            "sync_push_profile_settings_blob",
            session: session,
            params: [
                "p_profile_id": remoteProfileId,
                "p_platform": Self.settingsPlatform,
                "p_settings_json": settingsJSON
            ]
        )
    }

    func pullLibrary(session: AuthSession, remoteProfileId: Int) async throws -> [LibraryStoreItem] {
        var allItems: [RemoteLibraryItem] = []
        var offset = 0
        while true {
            let page: [RemoteLibraryItem] = try await rpc(
                "sync_pull_library",
                session: session,
                params: [
                    "p_profile_id": remoteProfileId,
                    "p_limit": Self.pullPageSize,
                    "p_offset": offset
                ]
            )
            allItems += page
            if page.count < Self.pullPageSize { break }
            offset += Self.pullPageSize
        }
        return allItems.map { remote in
            LibraryStoreItem(
                meta: remote.meta,
                addedAt: Self.date(fromMilliseconds: remote.addedAt)
            )
        }
    }

    func pushLibrary(session: AuthSession, remoteProfileId: Int) async throws {
        let payload = LibraryStore.items().map { item -> [String: Any] in
            var row: [String: Any] = [
                "content_id": item.meta.id,
                "content_type": item.meta.type,
                "name": item.meta.name,
                "poster": Self.jsonValue(item.meta.posterUrl),
                "poster_shape": "POSTER",
                "background": Self.jsonValue(item.meta.backgroundUrl),
                "description": Self.jsonValue(item.meta.description),
                "release_info": Self.jsonValue(item.meta.releaseInfo ?? item.meta.year.map(String.init)),
                "genres": item.meta.genres ?? [],
                "addon_base_url": NSNull(),
                "added_at": Self.milliseconds(from: item.addedAt)
            ]
            if let rating = item.meta.rating {
                row["imdb_rating"] = rating
            }
            return row
        }
        guard !payload.isEmpty else { return }
        try await rpcVoid(
            "sync_push_library",
            session: session,
            params: [
                "p_items": payload,
                "p_profile_id": remoteProfileId
            ]
        )
    }

    func pullWatched(session: AuthSession, remoteProfileId: Int) async throws -> [WatchedStoreItem] {
        var allItems: [RemoteWatchedItem] = []
        var page = 1
        while true {
            let remotePage: [RemoteWatchedItem] = try await rpc(
                "sync_pull_watched_items",
                session: session,
                params: [
                    "p_profile_id": remoteProfileId,
                    "p_page": page,
                    "p_page_size": Self.pullPageSize
                ]
            )
            allItems += remotePage
            if remotePage.count < Self.pullPageSize { break }
            page += 1
        }
        return allItems.map { remote in
            WatchedStoreItem(
                meta: remote.meta,
                watchedAt: Self.date(fromMilliseconds: remote.watchedAt)
            )
        }
    }

    func pushWatched(session: AuthSession, remoteProfileId: Int) async throws {
        let payload = WatchedStore.items().map { item -> [String: Any] in
            [
                "content_id": item.meta.id,
                "content_type": item.meta.type,
                "title": item.meta.name,
                "season": NSNull(),
                "episode": NSNull(),
                "watched_at": Self.milliseconds(from: item.watchedAt)
            ]
        }
        guard !payload.isEmpty else { return }
        try await rpcVoid(
            "sync_push_watched_items",
            session: session,
            params: [
                "p_items": payload,
                "p_profile_id": remoteProfileId
            ]
        )
    }

    func pullWatchProgress(session: AuthSession, remoteProfileId: Int) async throws -> [ContinueWatchingItem] {
        let remote: [RemoteWatchProgress] = try await rpc(
            "sync_pull_watch_progress",
            session: session,
            params: [
                "p_profile_id": remoteProfileId
            ]
        )
        var items: [ContinueWatchingItem] = []
        for entry in remote {
            let type = Self.normalizedContentType(entry.contentType)
            let existing = ContinueWatchingStore.item(for: entry.contentId)
            let fetchedMeta: NuvioMeta?
            if existing == nil {
                fetchedMeta = try? await catalogRepository.getMetadata(id: entry.contentId, type: type)
            } else {
                fetchedMeta = nil
            }
            let meta = existing?.meta ?? fetchedMeta ?? entry.fallbackMeta(type: type)
            let position = Double(entry.position) / 1000.0
            let duration = Double(entry.duration) / 1000.0
            guard duration > 0 else { continue }
            items.append(
                ContinueWatchingItem(
                    meta: meta,
                    streamUrl: existing?.streamUrl ?? "",
                    position: position,
                    duration: duration,
                    lastWatchedAt: Self.date(fromMilliseconds: entry.lastWatched)
                )
            )
        }
        return items
    }

    func pushWatchProgress(session: AuthSession, remoteProfileId: Int) async throws {
        let payload = ContinueWatchingStore.items().map { item -> [String: Any] in
            [
                "content_id": item.meta.id,
                "content_type": item.meta.type,
                "video_id": item.meta.id,
                "season": NSNull(),
                "episode": NSNull(),
                "position": Int64(item.position * 1000),
                "duration": Int64(item.duration * 1000),
                "last_watched": Self.milliseconds(from: item.lastWatchedAt),
                "progress_key": item.meta.id
            ]
        }
        guard !payload.isEmpty else { return }
        try await rpcVoid(
            "sync_push_watch_progress",
            session: session,
            params: [
                "p_entries": payload,
                "p_profile_id": remoteProfileId
            ]
        )
    }

    private func rpc<T: Decodable>(
        _ name: String,
        session authSession: AuthSession,
        params: [String: Any]
    ) async throws -> T {
        let data = try await rpcData(name, session: authSession, params: params)
        return try decoder.decode(T.self, from: data)
    }

    private func rpcVoid(
        _ name: String,
        session authSession: AuthSession,
        params: [String: Any]
    ) async throws {
        _ = try await rpcData(name, session: authSession, params: params)
    }

    private func rpcJSONObject(
        _ name: String,
        session authSession: AuthSession,
        params: [String: Any]
    ) async throws -> Any {
        let data = try await rpcData(name, session: authSession, params: params)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func rpcData(
        _ name: String,
        session authSession: AuthSession,
        params: [String: Any]
    ) async throws -> Data {
        guard AuthConfig.isConfigured else {
            throw AuthError(message: "Account backend is not configured.")
        }
        guard let url = URL(string: "\(AuthConfig.normalizedSupabaseURL)/rest/v1/rpc/\(name)") else {
            throw AuthError(message: "Invalid backend URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(AuthConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError(message: "No response from server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError(message: Self.serverErrorMessage(data: data, status: http.statusCode))
        }
        if data.isEmpty { return Data("null".utf8) }
        return data
    }

    private func exportSettings(localProfileId: String) -> [String: Any] {
        let defaults = ProfileSettings.store(for: localProfileId)
        var exported: [String: Any] = [:]
        SettingsKey.all.forEach { key in
            guard let value = defaults.object(forKey: key),
                  let encoded = Self.encodeSettingValue(value) else {
                return
            }
            exported[key] = encoded
        }
        return exported
    }

    private func importSettings(_ remote: [String: Any], localProfileId: String) {
        let defaults = ProfileSettings.store(for: localProfileId)
        SettingsKey.all.forEach { key in
            guard let encoded = remote[key] as? [String: Any],
                  let value = Self.decodeSettingValue(encoded) else {
                return
            }
            defaults.set(value, forKey: key)
        }
    }

    private static func encodeSettingValue(_ value: Any) -> [String: Any]? {
        if let string = value as? String {
            return ["type": "string", "value": string]
        }
        if let bool = value as? Bool {
            return ["type": "boolean", "value": bool]
        }
        if let int = value as? Int {
            return ["type": "int", "value": int]
        }
        if let double = value as? Double {
            return ["type": "double", "value": double]
        }
        if let float = value as? Float {
            return ["type": "float", "value": float]
        }
        return nil
    }

    private static func decodeSettingValue(_ encoded: [String: Any]) -> Any? {
        guard let type = encoded["type"] as? String else { return nil }
        let value = encoded["value"]
        switch type {
        case "string":
            return value as? String
        case "boolean":
            return value as? Bool
        case "int":
            if let int = value as? Int { return int }
            return (value as? NSNumber)?.intValue
        case "long":
            if let int = value as? Int { return int }
            return (value as? NSNumber)?.intValue
        case "float", "double":
            if let double = value as? Double { return double }
            return (value as? NSNumber)?.doubleValue
        default:
            return nil
        }
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
    }

    private static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    fileprivate static func normalizedContentType(_ type: String) -> String {
        type.lowercased() == "tv" ? "series" : type
    }

    private static func serverErrorMessage(data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error", "error_code"] {
                if let message = obj[key] as? String, !message.isEmpty {
                    return message
                }
            }
        }
        return "Sync request failed (\(status))"
    }
}

private struct RemoteProfile: Decodable {
    let profileIndex: Int
    let name: String
    let avatarId: String?

    enum CodingKeys: String, CodingKey {
        case profileIndex
        case name
        case avatarId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileIndex = try container.decode(Int.self, forKey: .profileIndex)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        avatarId = try? container.decodeIfPresent(String.self, forKey: .avatarId)
    }
}

private struct RemoteLibraryItem: Decodable {
    let contentId: String
    let contentType: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: Double?
    let genres: [String]
    let addedAt: Int64

    var meta: NuvioMeta {
        let parsedYear = releaseInfo.flatMap { Int(String($0.prefix(4))) }
        return NuvioMeta(
            id: contentId,
            name: name.isEmpty ? contentId : name,
            description: description,
            posterUrl: poster,
            backgroundUrl: background,
            logoUrl: nil,
            imdbId: nil,
            tmdbId: nil,
            type: SupabaseSyncClient.normalizedContentType(contentType),
            year: parsedYear,
            genres: genres,
            rating: imdbRating,
            releaseInfo: releaseInfo,
            runtime: nil,
            cast: nil,
            director: nil,
            writer: nil,
            certification: nil,
            country: nil,
            released: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case contentId
        case contentType
        case name
        case poster
        case background
        case description
        case releaseInfo
        case imdbRating
        case genres
        case addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentId = try container.decode(String.self, forKey: .contentId)
        contentType = try container.decode(String.self, forKey: .contentType)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        poster = try? container.decodeIfPresent(String.self, forKey: .poster)
        background = try? container.decodeIfPresent(String.self, forKey: .background)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        releaseInfo = try? container.decodeIfPresent(String.self, forKey: .releaseInfo)
        imdbRating = try? container.decodeIfPresent(Double.self, forKey: .imdbRating)
        genres = (try? container.decode([String].self, forKey: .genres)) ?? []
        addedAt = (try? container.decode(Int64.self, forKey: .addedAt)) ?? 0
    }
}

private struct RemoteWatchedItem: Decodable {
    let contentId: String
    let contentType: String
    let title: String
    let watchedAt: Int64

    var meta: NuvioMeta {
        NuvioMeta(
            id: contentId,
            name: title.isEmpty ? contentId : title,
            description: nil,
            posterUrl: nil,
            backgroundUrl: nil,
            logoUrl: nil,
            imdbId: nil,
            tmdbId: nil,
            type: SupabaseSyncClient.normalizedContentType(contentType),
            year: nil,
            genres: nil,
            rating: nil,
            releaseInfo: nil,
            runtime: nil,
            cast: nil,
            director: nil,
            writer: nil,
            certification: nil,
            country: nil,
            released: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case contentId
        case contentType
        case title
        case watchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentId = try container.decode(String.self, forKey: .contentId)
        contentType = try container.decode(String.self, forKey: .contentType)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        watchedAt = (try? container.decode(Int64.self, forKey: .watchedAt)) ?? 0
    }
}

private struct RemoteWatchProgress: Decodable {
    let contentId: String
    let contentType: String
    let videoId: String
    let season: Int?
    let episode: Int?
    let position: Int64
    let duration: Int64
    let lastWatched: Int64
    let progressKey: String

    func fallbackMeta(type: String) -> NuvioMeta {
        NuvioMeta(
            id: contentId,
            name: contentId,
            description: nil,
            posterUrl: nil,
            backgroundUrl: nil,
            logoUrl: nil,
            imdbId: nil,
            tmdbId: nil,
            type: type,
            year: nil,
            genres: nil,
            rating: nil,
            releaseInfo: nil,
            runtime: nil,
            cast: nil,
            director: nil,
            writer: nil,
            certification: nil,
            country: nil,
            released: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case contentId
        case contentType
        case videoId
        case season
        case episode
        case position
        case duration
        case lastWatched
        case progressKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentId = try container.decode(String.self, forKey: .contentId)
        contentType = try container.decode(String.self, forKey: .contentType)
        videoId = (try? container.decode(String.self, forKey: .videoId)) ?? contentId
        season = try? container.decodeIfPresent(Int.self, forKey: .season)
        episode = try? container.decodeIfPresent(Int.self, forKey: .episode)
        position = (try? container.decode(Int64.self, forKey: .position)) ?? 0
        duration = (try? container.decode(Int64.self, forKey: .duration)) ?? 0
        lastWatched = (try? container.decode(Int64.self, forKey: .lastWatched)) ?? 0
        progressKey = (try? container.decode(String.self, forKey: .progressKey)) ?? contentId
    }
}
