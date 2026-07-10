import Foundation

/// Converts cached torrent results into the TorBox-backed source shown by the
/// Android app as "TB Instant". Cache checks never add torrents to the account.
struct TorboxInstantService {
    private let store: UserDefaults
    private let session: URLSession

    init(store: UserDefaults, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    func prepare(_ streams: [NuvioStream]) async -> [NuvioStream] {
        guard DebridProviderKind(settingsValue: store.string(forKey: SettingsKey.debridProvider)) == .torbox else {
            return streams
        }
        let key = (store.string(forKey: SettingsKey.debridApiKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return streams }

        let direct = streams.filter { !$0.isDebridResolvable || $0.isTorboxInstant }
        let torrents = streams.filter { $0.isDebridResolvable && !$0.isTorboxInstant }
        let hashes = Array(Set(torrents.compactMap { $0.infoHash?.lowercased() })).sorted()
        guard !hashes.isEmpty else { return streams }

        guard let cached = await checkCached(hashes: hashes, apiKey: key) else {
            return streams
        }
        let instant = torrents.compactMap { stream -> NuvioStream? in
            guard let hash = stream.infoHash?.lowercased(), let item = cached[hash] else { return nil }
            return stream.asTorboxInstant(cachedName: item.name, cachedSize: item.size)
        }
        return direct + instant
    }

    private func checkCached(hashes: [String], apiKey: String) async -> [String: CachedItem]? {
        guard let url = URL(string: "https://api.torbox.app/v1/api/torrents/checkcached?format=object") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(CheckCachedRequest(hashes: hashes))

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            let envelope = try JSONDecoder().decode(CheckCachedEnvelope.self, from: data)
            guard envelope.success != false else { return nil }
            return Dictionary(uniqueKeysWithValues: (envelope.data ?? [:]).map { ($0.key.lowercased(), $0.value) })
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }
}

private extension NuvioStream {
    var isTorboxInstant: Bool {
        name?.localizedCaseInsensitiveContains("TB Instant") == true
    }
}

private struct CheckCachedRequest: Encodable {
    let hashes: [String]
}

private struct CheckCachedEnvelope: Decodable {
    let success: Bool?
    let data: [String: CachedItem]?
}

private struct CachedItem: Decodable {
    let name: String?
    let size: Int64?
}
