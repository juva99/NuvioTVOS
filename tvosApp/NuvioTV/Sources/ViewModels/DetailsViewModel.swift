//
//  DetailsViewModel.swift
//  NuvioTV
//
//  Created by Claude Code
//  ViewModel for content details screen
//

import Foundation
import Combine

@MainActor
class DetailsViewModel: ObservableObject {
    @Published private(set) var uiState = DetailsUiState()

    private let repository: CatalogRepository
    private var streamTask: Task<Void, Never>?

    init(repository: CatalogRepository) {
        self.repository = repository
    }

    func loadDetails(id: String, type: String) {
        Task {
            uiState = DetailsUiState(isLoading: true, error: nil)

            do {
                let meta = try await repository.getMetadata(id: id, type: type)
                uiState.meta = meta
                uiState.isInWatchlist = LibraryStore.contains(metaId: meta.id, type: meta.type)
                uiState.isWatched = WatchedStore.contains(metaId: meta.id, type: meta.type)
                uiState.isLoading = false

                // Movies stream off the title id; series stream per episode, loaded
                // on demand when the user picks one (see prepareStreams).
                if !meta.isSeries {
                    prepareStreams(forId: id, type: meta.type)
                }
            } catch {
                uiState.isLoading = false
                uiState.error = error.localizedDescription
            }
        }
    }

    /// Load the playable streams for a given title/episode id, replacing any
    /// previously loaded streams so the picker never shows stale results.
    ///
    /// Streams arrive progressively: the first add-on to respond is shown right
    /// away and later add-ons are appended as they land, rather than blocking on
    /// every add-on before showing anything. `isLoadingStreams` stays true until
    /// every add-on has reported, so smart auto-play still waits for the full set.
    func prepareStreams(forId streamId: String, type: String) {
        // Cancel any in-flight fetch (e.g. from a previously selected episode) so
        // its late results can't overwrite the newly requested ones.
        streamTask?.cancel()
        streamTask = Task {
            uiState.streams = []
            uiState.isLoadingStreams = true
            for await streams in repository.streamsProgressively(id: streamId, type: type) {
                if Task.isCancelled { return }
                uiState.streams = streams
            }
            if !Task.isCancelled {
                uiState.isLoadingStreams = false
            }
        }
    }

    func toggleWatchlist() {
        guard let meta = uiState.meta else { return }
        uiState.isInWatchlist = LibraryStore.toggle(meta: meta)
    }

    func toggleWatched() {
        guard let meta = uiState.meta else { return }
        uiState.isWatched = WatchedStore.toggle(meta: meta)
    }

    func rateContent(rating: Int) {
        uiState.userRating = rating
        // TODO: Submit rating to ProfileRepository via profile preferences
        // The Rust SDK ProfileManager stores preferences in Profile.preferences
        // Need to update profile with ratings in preferences field
    }
}
