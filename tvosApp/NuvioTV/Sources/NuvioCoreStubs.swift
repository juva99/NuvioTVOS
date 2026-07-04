import Foundation
import Combine

// MARK: - Stub types replacing NuvioCore Rust FFI types

/// Stub for Rust-generated Profile type
public struct Profile: Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isPinProtected: Bool
    public var isAdmin: Bool
    public var avatarId: String

    public init(id: String, name: String, isPinProtected: Bool = false, isAdmin: Bool = false, avatarId: String = "default") {
        self.id = id
        self.name = name
        self.isPinProtected = isPinProtected
        self.isAdmin = isAdmin
        self.avatarId = avatarId
    }
}

/// Stub for Rust-generated StremioMeta type (used by Library and Search ViewModels)
public struct StremioMeta: Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var contentType: String
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var imdbRating: String?
    public var year: Int32?
    public var genres: [String]?
    public var runtime: String?

    public init(id: String, name: String, contentType: String, poster: String? = nil,
                background: String? = nil, logo: String? = nil, description: String? = nil,
                releaseInfo: String? = nil, imdbRating: String? = nil, year: Int32? = nil,
                genres: [String]? = nil, runtime: String? = nil) {
        self.id = id
        self.name = name
        self.contentType = contentType
        self.poster = poster
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.year = year
        self.genres = genres
        self.runtime = runtime
    }
}

/// Stub for Rust-generated WatchedItem type
public struct WatchedItem: Equatable, Hashable, Identifiable {
    public var id: String
    public var metaId: String
    public var metaType: String
    public var progressPercent: Double
    public var lastWatched: Int64

    public init(id: String, metaId: String, metaType: String, progressPercent: Double, lastWatched: Int64) {
        self.id = id
        self.metaId = metaId
        self.metaType = metaType
        self.progressPercent = progressPercent
        self.lastWatched = lastWatched
    }
}

// MARK: - ProfileManager stub (replaces Rust FFI class)

/// Pure Swift stub for ProfileManager — persists via UserDefaults
public class ProfileManager {
    static let profilesChangedNotification = Notification.Name("nuvio.tv.profiles.changed")

    private static let profilesKey = "nuvio.profiles"
    private static let activePinKey = "nuvio.active_profile_id"
    private static let maxProfiles = 6

    public init(baseDir: String) throws {
        // No-op for stub — we use UserDefaults
    }

    public func getProfiles() throws -> [Profile] {
        guard let data = UserDefaults.standard.data(forKey: Self.profilesKey),
              let decoded = try? JSONDecoder().decode([StoredProfile].self, from: data) else {
            return []
        }
        return decoded.map { $0.toProfile() }
    }

    public func createProfile(input: CreateProfileInput) throws -> Profile {
        var profiles = (try? getProfiles()) ?? []
        let id = nextProfileId(in: profiles)
        let profile = Profile(
            id: id,
            name: input.name,
            isPinProtected: input.pin != nil,
            isAdmin: false,
            avatarId: input.avatarId ?? "default"
        )
        profiles.append(profile)
        saveProfiles(profiles)
        return profile
    }

    public func getActiveProfile() throws -> Profile? {
        let profiles = (try? getProfiles()) ?? []
        if let id = UserDefaults.standard.string(forKey: Self.activePinKey) {
            return profiles.first(where: { $0.id == id })
        }
        return profiles.first
    }

    public func switchProfile(id: String) throws {
        UserDefaults.standard.set(id, forKey: Self.activePinKey)
    }

    public func deleteProfile(id: String) throws {
        var profiles = (try? getProfiles()) ?? []
        profiles.removeAll(where: { $0.id == id })
        saveProfiles(profiles)
    }

    public func updateProfileAvatar(id: String, avatarId: String) throws {
        var profiles = (try? getProfiles()) ?? []
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].avatarId = avatarId
        saveProfiles(profiles)
    }

    public func replaceProfiles(_ profiles: [Profile]) throws {
        saveProfiles(profiles)
        if let activeId = UserDefaults.standard.string(forKey: Self.activePinKey),
           profiles.contains(where: { $0.id == activeId }) {
            return
        }
        if let first = profiles.first {
            UserDefaults.standard.set(first.id, forKey: Self.activePinKey)
        }
    }

    public func verifyPin(id: String, pin: String) throws -> Bool {
        // Stub: always valid (real PIN verification would come from Rust)
        return true
    }

    private func saveProfiles(_ profiles: [Profile]) {
        let stored = profiles.map { StoredProfile(from: $0) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
            NotificationCenter.default.post(name: Self.profilesChangedNotification, object: nil)
        }
    }

    private func nextProfileId(in profiles: [Profile]) -> String {
        let used = Set(profiles.compactMap { Int($0.id) })
        if let next = (1...Self.maxProfiles).first(where: { !used.contains($0) }) {
            return String(next)
        }
        return UUID().uuidString
    }
}

// Codable helper for UserDefaults persistence
private struct StoredProfile: Codable {
    var id: String
    var name: String
    var isPinProtected: Bool
    var isAdmin: Bool
    var avatarId: String

    init(from profile: Profile) {
        self.id = profile.id
        self.name = profile.name
        self.isPinProtected = profile.isPinProtected
        self.isAdmin = profile.isAdmin
        self.avatarId = profile.avatarId
    }

    func toProfile() -> Profile {
        Profile(id: id, name: name, isPinProtected: isPinProtected, isAdmin: isAdmin, avatarId: avatarId)
    }
}

/// Input for creating a profile
public struct CreateProfileInput {
    public var name: String
    public var profileType: ProfileTypeStub
    public var avatarId: String?
    public var maxAgeRating: String?
    public var pin: String?

    public init(name: String, profileType: ProfileTypeStub = .adult, avatarId: String? = nil, maxAgeRating: String? = nil, pin: String? = nil) {
        self.name = name
        self.profileType = profileType
        self.avatarId = avatarId
        self.maxAgeRating = maxAgeRating
        self.pin = pin
    }
}

public enum ProfileTypeStub {
    case admin, adult, kids
}

// Alias so ProfileViewModel can use .admin / .adult without changes
typealias ProfileType = ProfileTypeStub

// MARK: - ProfileViewModel (pure Swift, no Rust dependency)

@MainActor
public class ProfileViewModel: ObservableObject {
    @Published public var profiles: [Profile] = []
    @Published public var activeProfile: Profile?
    @Published public var isPinEntryVisible = false
    @Published public var pinError: String?
    @Published public var isLoading = false
    @Published public var pendingProfileId: String?

    /// Fires only when the user explicitly picks a profile (who's-watching
    /// card or PIN confirmation) — never when a sync refreshes
    /// `activeProfile`. Screens navigate on this, not on `$activeProfile`.
    public let profileChosen = PassthroughSubject<Profile, Never>()

    private let profileManager: ProfileManager?

    public init(profileManager: ProfileManager? = nil) {
        if let manager = profileManager {
            self.profileManager = manager
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
            do {
                self.profileManager = try ProfileManager(baseDir: documentsPath)
            } catch {
                print("Failed to initialize ProfileManager: \(error)")
                self.profileManager = nil
            }
        }
        loadProfiles()
        loadActiveProfile()
    }

    public func loadProfiles() {
        guard let manager = profileManager else {
            // Seed a default profile so the UI isn't empty
            if profiles.isEmpty {
                profiles = [Profile(id: "1", name: "Nuvio User", isPinProtected: false, isAdmin: true, avatarId: "default")]
            }
            return
        }
        do {
            var list = try manager.getProfiles()
            if list.isEmpty {
                let input = CreateProfileInput(name: "Nuvio Guest", profileType: .admin, avatarId: "default")
                _ = try manager.createProfile(input: input)
                list = try manager.getProfiles()
            }
            self.profiles = list
        } catch {
            print("Failed to load profiles: \(error)")
        }
    }

    public func loadActiveProfile() {
        guard let manager = profileManager else {
            let profile = profiles.first
            // Scope watch history and settings to this profile before the UI reads them.
            ContinueWatchingStore.setActiveProfile(profile?.id)
            LibraryStore.setActiveProfile(profile?.id)
            WatchedStore.setActiveProfile(profile?.id)
            CollectionsStore.setActiveProfile(profile?.id)
            ProfileSettings.setActiveProfile(profile?.id)
            self.activeProfile = profile
            return
        }
        do {
            let profile = try manager.getActiveProfile()
            // Scope watch history and settings to this profile before the UI reads them.
            ContinueWatchingStore.setActiveProfile(profile?.id)
            LibraryStore.setActiveProfile(profile?.id)
            WatchedStore.setActiveProfile(profile?.id)
            CollectionsStore.setActiveProfile(profile?.id)
            ProfileSettings.setActiveProfile(profile?.id)
            self.activeProfile = profile
        } catch {
            print("Failed to load active profile: \(error)")
        }
    }

    public func createProfile(name: String, pin: String?, avatarId: String = "default") {
        guard let manager = profileManager else { return }
        isLoading = true
        let input = CreateProfileInput(name: name, profileType: .adult, avatarId: avatarId, pin: pin)
        Task {
            do {
                let newProfile = try manager.createProfile(input: input)
                // Start the new profile as a copy of the current settings; it
                // diverges independently from then on.
                ProfileSettings.seedNewProfile(newProfile.id)
                loadProfiles()
                isLoading = false
            } catch {
                print("Failed to create profile: \(error)")
                isLoading = false
            }
        }
    }

    public func updateActiveProfileAvatar(_ avatarId: String) {
        guard let id = activeProfile?.id else { return }
        updateProfileAvatar(id: id, avatarId: avatarId)
    }

    public func updateProfileAvatar(id: String, avatarId: String) {
        guard !avatarId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard let manager = profileManager else {
            if let index = profiles.firstIndex(where: { $0.id == id }) {
                profiles[index].avatarId = avatarId
                if activeProfile?.id == id {
                    activeProfile = profiles[index]
                }
            }
            return
        }

        do {
            try manager.updateProfileAvatar(id: id, avatarId: avatarId)
            loadProfiles()
            loadActiveProfile()
        } catch {
            print("Failed to update profile avatar: \(error)")
        }
    }

    public func requestSwitch(to profile: Profile) {
        if profile.isPinProtected {
            self.pendingProfileId = profile.id
            self.isPinEntryVisible = true
        } else {
            switchProfile(id: profile.id, pin: nil)
        }
    }

    public func verifyAndSwitch(pin: String) {
        guard let id = pendingProfileId else { return }
        switchProfile(id: id, pin: pin)
    }

    private func switchProfile(id: String, pin: String?) {
        if let pin = pin, !pin.isEmpty {
            // Stub: accept any PIN
            _ = pin
        }
        do {
            try profileManager?.switchProfile(id: id)
            loadActiveProfile()
            isPinEntryVisible = false
            pendingProfileId = nil
            pinError = nil
            if let profile = activeProfile {
                profileChosen.send(profile)
            }
        } catch {
            print("Failed to switch profile: \(error)")
        }
    }

    public func applyRemoteProfiles(_ remoteProfiles: [Profile]) {
        guard !remoteProfiles.isEmpty else { return }
        do {
            try profileManager?.replaceProfiles(remoteProfiles)
            loadProfiles()
            // Unconditional: besides refreshing the profile object this scopes
            // the watch-state stores (setActiveProfile) so the sync's merges
            // that follow land in the right per-profile buckets. Navigation
            // away from who's-watching listens to `profileChosen`, not
            // `activeProfile`, so this can't yank the user into a profile.
            loadActiveProfile()
        } catch {
            print("Failed to apply remote profiles: \(error)")
        }
    }

    public func resetForSignedOut() {
        let guest = Profile(
            id: "guest",
            name: "Nuvio Guest",
            isPinProtected: false,
            isAdmin: true,
            avatarId: "default"
        )
        // Collect ids before replacing the profile list so their settings
        // suites can be deleted below.
        let previousIds = ((try? profileManager?.getProfiles()) ?? profiles).map(\.id)
        do {
            try profileManager?.replaceProfiles([guest])
        } catch {
            print("Failed to reset signed-out profile: \(error)")
        }
        profiles = [guest]
        activeProfile = nil

        // Sign-out is a full local reset: no watch history, watched marks,
        // library items, add-ons, API keys, or preferences may survive into
        // the next session. Remote data stays on the account — the sync
        // manager is already detached (auth state is signed out), so these
        // deletions never push to the server.
        ContinueWatchingStore.eraseAllProfiles()
        LibraryStore.eraseAllProfiles()
        WatchedStore.eraseAllProfiles()
        CollectionsStore.eraseAllProfiles()
        // Cover the whole local id space (1-6 + guest), not just the current
        // list, so suites left behind by previously deleted profiles go too.
        ProfileSettings.eraseAll(profileIds: previousIds + (1...6).map(String.init) + [guest.id])
        NuvioSyncManager.eraseProfileIndexBindings()

        ContinueWatchingStore.setActiveProfile(nil)
        LibraryStore.setActiveProfile(nil)
        WatchedStore.setActiveProfile(nil)
        CollectionsStore.setActiveProfile(nil)
        ProfileSettings.clearActiveProfile()
    }
}

/// Stub for Rust-generated StremioService
public class StremioService {
    public init() throws {}
    
    public func getCatalog(addonId: String, contentType: String, catalogId: String, page: Int32, search: String?) async throws -> [StremioMeta] {
        // Return mock search results
        if let query = search, !query.isEmpty {
            return [
                StremioMeta(id: "mock1", name: "\(query) Result 1", contentType: contentType),
                StremioMeta(id: "mock2", name: "\(query) Result 2", contentType: contentType)
            ]
        }
        return []
    }
}
