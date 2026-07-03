import SwiftUI

private enum LibraryGridMetrics {
    static let posterWidth: CGFloat = 210
    static let posterHeight: CGFloat = 315
    static let posterGap: CGFloat = 28
    static let cardHorizontalPadding: CGFloat = 10
    static let cardVerticalPadding: CGFloat = 14
    static let columnWidth: CGFloat = posterWidth + cardHorizontalPadding * 2
    static let columnSpacing: CGFloat = posterGap - cardHorizontalPadding * 2
}

public struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    let onContentClick: (String, String) -> Void
    @FocusState private var focusedItemID: String?
    /// Last card focused in the grid, kept so returning from details (which
    /// steals focus and nils `focusedItemID`) restores that card instead of
    /// snapping back to the top of the grid.
    @State private var lastFocusedItemID: String?
    @State private var shouldRestoreFocus = false
    /// Card to actively re-focus once the Details overlay dismisses; captured
    /// when the tab view gets disabled (overlay up), consumed on re-enable.
    @State private var overlayRestoreItemID: String?
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(SettingsKey.amoled) private var amoled = false
    @AppStorage(SettingsKey.bodyColor) private var bodyColor = SettingsBackground.charcoal.rawValue

    public init(viewModel: LibraryViewModel, onContentClick: @escaping (String, String) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onContentClick = onContentClick
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            Color.nuvioBackground(amoled: amoled, body: bodyColor).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("Library")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(.white)

                // Controls
                HStack(spacing: 16) {
                    FilterMenu(label: "Sort: \(viewModel.sortOption.rawValue)") {
                        ForEach(LibraryViewModel.SortOption.allCases) { option in
                            Button { viewModel.sortOption = option } label: {
                                menuItem(option.rawValue, selected: viewModel.sortOption == option)
                            }
                        }
                    }

                    FilterMenu(label: "Group: \(viewModel.groupOption.rawValue)") {
                        ForEach(LibraryViewModel.GroupOption.allCases) { option in
                            Button { viewModel.groupOption = option } label: {
                                menuItem(option.rawValue, selected: viewModel.groupOption == option)
                            }
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.sortedAndGroupedItems.keys.sorted(), id: \.self) { group in
                            if viewModel.groupOption != .none {
                                Text(group.capitalized)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: LibraryGridMetrics.posterGap) {
                                ForEach(viewModel.sortedAndGroupedItems[group] ?? [], id: \.id) { item in
                                    LibraryItemButton(item: item, externalFocus: $focusedItemID) {
                                        onContentClick(item.id, item.contentType)
                                    }
                                    .disabled(overlayRestoreItemID != nil && overlayRestoreItemID != item.id)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusSection()
                .defaultFocusIfAvailable($focusedItemID, shouldRestoreFocus ? lastFocusedItemID : nil)
            }
            .padding(.horizontal, 80)
            .padding(.top, 56)
        }
        .onChange(of: focusedItemID) { newValue in
            if let newValue {
                lastFocusedItemID = newValue
                shouldRestoreFocus = false
                // Restoration complete -- lift the focus restriction.
                if newValue == overlayRestoreItemID { overlayRestoreItemID = nil }
            } else if lastFocusedItemID != nil {
                shouldRestoreFocus = true
            }
        }
        // Overlay dismissal re-places focus geometrically without consulting
        // `defaultFocus`. While `overlayRestoreItemID` is set every other card
        // is unfocusable, so the engine can only land back on the saved card
        // -- no scroll-to-top flash. See TVHomeView for the full story.
        .onChange(of: isEnabled) { enabled in
            if !enabled {
                overlayRestoreItemID = focusedItemID ?? lastFocusedItemID
            } else if let target = overlayRestoreItemID {
                for delay in [0.12, 0.45] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if overlayRestoreItemID == target { focusedItemID = target }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if overlayRestoreItemID == target { overlayRestoreItemID = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func menuItem(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: LibraryGridMetrics.columnWidth, maximum: LibraryGridMetrics.columnWidth),
            spacing: LibraryGridMetrics.columnSpacing,
            alignment: .top
        )]
    }
}

struct LibraryItemButton: View {
    let item: StremioMeta
    var externalFocus: FocusState<String?>.Binding? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.posterLabels) private var posterLabels = false
    @AppStorage(SettingsKey.smoothFocus) private var smoothFocus = true
    @AppStorage(SettingsKey.focusHighlighter) private var focusHighlighter = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: item.poster ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .frame(width: LibraryGridMetrics.posterWidth, height: LibraryGridMetrics.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    WatchedCheckmarkBadge(metaId: item.id, type: item.contentType)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(isFocused ? focusBorderColor : Color.clear, lineWidth: focusHighlighter ? 5 : 3)
                )
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0.2), radius: isFocused ? 12 : 4)
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(smoothFocus ? .spring(response: 0.28, dampingFraction: 0.72) : nil, value: isFocused)
                
                if posterLabels {
                    Text(item.name)
                        .font(.system(size: 18, weight: isFocused ? .semibold : .medium))
                        .foregroundColor(isFocused ? .white : .white.opacity(0.6))
                        .lineLimit(1)
                        .frame(width: LibraryGridMetrics.posterWidth, alignment: .leading)
                        .animation(smoothFocus ? .spring(response: 0.28, dampingFraction: 0.72) : nil, value: isFocused)
                }
            }
            .frame(width: LibraryGridMetrics.posterWidth, alignment: .topLeading)
            .padding(.horizontal, LibraryGridMetrics.cardHorizontalPadding)
            .padding(.vertical, LibraryGridMetrics.cardVerticalPadding)
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .modifier(ExternalFocusBinding(binding: externalFocus, id: item.id))
        .focusEffectDisabledIfAvailable()
        .zIndex(isFocused ? 1 : 0)
    }

    private var focusBorderColor: Color {
        .white.opacity(0.86)
    }

    private var cardCornerRadius: CGFloat {
        16
    }
}
