import TVServices

/// Populates the Apple TV home-screen Top Shelf row from the Continue Watching
/// feed the main app mirrors into the shared App Group. Reads
/// `TopShelfFeedStore` (add `TopShelfFeed.swift` to this target's membership).
final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let feed = TopShelfFeedStore.read(), !feed.entries.isEmpty else {
            completionHandler(nil)
            return
        }

        let items = feed.entries.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: entry.contentId)
            item.title = entry.title
            item.imageShape = .poster

            if let image = entry.imageURL, let url = URL(string: image) {
                item.setImageURL(url, for: .screenScale1x)
                item.setImageURL(url, for: .screenScale2x)
            }
            if let progress = entry.progress {
                item.playbackProgress = progress
            }
            if let link = entry.deepLinkURL {
                let action = TVTopShelfAction(url: link)
                item.displayAction = action
                item.playAction = action
            }
            return item
        }

        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "Continue Watching"
        completionHandler(TVTopShelfSectionedContent(sections: [collection]))
    }
}
