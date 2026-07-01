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
    func prepareStreams(forId streamId: String, type: String) {
        Task {
            uiState.streams = []
            uiState.isLoadingStreams = true
            do {
                let streams = try await repository.getStreams(id: streamId, type: type)
                uiState.streams = streams
                uiState.isLoadingStreams = false
            } catch {
                // Streams failure is not critical, just log it
                uiState.isLoadingStreams = false
                print("Failed to load streams: \(error.localizedDescription)")
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
