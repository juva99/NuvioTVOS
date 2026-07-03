import Foundation
import Combine

@MainActor
public class LibraryViewModel: ObservableObject {
    @Published public var items: [StremioMeta] = []
    @Published public var sortOption: SortOption = .dateAdded
    @Published public var groupOption: GroupOption = .none
    /// Last focused card, kept here (outside the view, like
    /// `TVHomeStore.lastFocusedCardID`) so it survives the details push and
    /// returning restores that card instead of snapping to the top.
    public var lastFocusedItemID: String?
    private var libraryObserver: NSObjectProtocol?
    
    public enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case title = "Title"
        case year = "Year"
        
        public var id: String { self.rawValue }
    }
    
    public enum GroupOption: String, CaseIterable, Identifiable {
        case none = "None"
        case type = "Type"
        
        public var id: String { self.rawValue }
    }
    
    public init() {
        loadLibrary()
        libraryObserver = NotificationCenter.default.addObserver(
            forName: LibraryStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadLibrary()
            }
        }
    }

    deinit {
        if let libraryObserver {
            NotificationCenter.default.removeObserver(libraryObserver)
        }
    }
    
    public func loadLibrary() {
        self.items = LibraryStore.items().map(\.stremioMeta)
    }
    
    public var sortedAndGroupedItems: [String: [StremioMeta]] {
        var result: [String: [StremioMeta]] = [:]
        
        let sorted: [StremioMeta]
        switch sortOption {
        case .dateAdded:
            sorted = items
        case .title:
            sorted = items.sorted { $0.name < $1.name }
        case .year:
            sorted = items.sorted { ($0.releaseInfo ?? "") > ($1.releaseInfo ?? "") }
        }
        
        switch groupOption {
        case .none:
            result["All"] = sorted
        case .type:
            result = Dictionary(grouping: sorted, by: { $0.contentType })
        }
        
        return result
    }
}
