import SwiftUI

// MARK: - Catalogue, v4
// Modern shopping layout: clean search bar at the top, filter chips
// (All / Available / Sold out), a sort menu, and platform cards in
// a 2-column grid. Live data from the catalogue API on every launch
// and on pull-to-refresh. While loading the ring spinner shows; on
// failure an error state with retry shows. Tap a card to open the
// platform detail as a native sheet with detents.

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var filter: CatalogFilter = .all
    @State private var sort: CatalogSort = .priceLowToHigh
    @State private var selectedPlatform: Platform?
    @State private var loadError: String?
    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    searchBar
                    filterRow
                    content
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.psBackground)
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                dismissKeyboardButton
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        if appState.isRefreshing {
                            PSRingSpinner(diameter: 20, lineWidth: 2)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(appState.isRefreshing)
                    .accessibilityLabel("Refresh catalogue")
                }
            }
            .refreshable { await load() }
            .sheet(item: $selectedPlatform) { platform in
                PlatformDetailView(platform: platform)
                    .psSheetDetents()
            }
            .task { await load() }
            .safeAreaPadding(.bottom, 8)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        await appState.refreshCatalogue()
        if appState.liveState != .live {
            loadError = "The latest catalogue could not be loaded. Check your connection and try again."
        }
    }

    private var filteredPlatforms: [Platform] {
        var list = appState.platforms
        switch filter {
        case .all:
            break
        case .available:
            list = list.filter { !$0.isSoldOut }
        case .soldOut:
            list = list.filter { $0.isSoldOut }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.tagline.localizedCaseInsensitiveContains(query)
            }
        }
        switch sort {
        case .priceLowToHigh:
            list.sort { $0.priceKES < $1.priceKES }
        case .priceHighToLow:
            list.sort { $0.priceKES > $1.priceKES }
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return list
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LogoLockupView(height: 32)
            Text("Shared subscriptions, one slot at a time.")
                .font(.psTitle)
            if appState.liveState == .live, let total = appState.liveTotalSlots {
                Text("\(appState.platformCount) platforms · \(total) slots in rotation")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.psMuted)
                .accessibilityHidden(true)
            TextField("Search platforms", text: $searchText)
                .font(.psBody)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Self.hideKeyboard() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.psMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CatalogFilter.allCases, id: \.self) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.label)
                                .font(.psBody)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(filter == option ? Color.psPrimary : Color.psSurface)
                                .foregroundStyle(filter == option ? .white : .psText)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.psBorder, lineWidth: 1)
                                        .opacity(filter == option ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show \(option.label.lowercased()) platforms")
                    }
                }
            }
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(CatalogSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label(sort.shortLabel, systemImage: "arrow.up.arrow.down")
                    .font(.psCaption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.psSurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.psBorder, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Sort catalogue, currently \(sort.label)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && appState.liveState != .live {
            HStack {
                Spacer()
                PSRingSpinner(diameter: 32, lineWidth: 3)
                Spacer()
            }
            .padding(.vertical, 48)
        } else if let loadError, appState.liveState != .live {
            PSErrorState(message: loadError) {
                Task { await load() }
            }
        } else if filteredPlatforms.isEmpty {
            PSEmptyState(
                systemImage: "magnifyingglass",
                title: "No platforms match.",
                body: "Try a different search, or pick another filter."
            )
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredPlatforms) { platform in
                    SlotCard(
                        platform: platform,
                        isOnWaitlist: appState.waitlist.contains(platform.id),
                        onWaitlistTap: {
                            if appState.waitlist.contains(platform.id) {
                                appState.leaveWaitlist(platformId: platform.id)
                            } else {
                                appState.joinWaitlist(platformId: platform.id)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPlatform = platform }
                }
            }
            .hideKeyboardOnTap()
            Text("1 slot = 1 device. Prices are in Kenyan shillings.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
                .padding(.top, 4)
        }
    }
}

enum CatalogFilter: String, CaseIterable {
    case all
    case available
    case soldOut

    var label: String {
        switch self {
        case .all: return "All"
        case .available: return "Available"
        case .soldOut: return "Sold out"
        }
    }
}

enum CatalogSort: String, CaseIterable {
    case priceLowToHigh
    case priceHighToLow
    case name

    var label: String {
        switch self {
        case .priceLowToHigh: return "Price: low to high"
        case .priceHighToLow: return "Price: high to low"
        case .name: return "Name: A to Z"
        }
    }

    var shortLabel: String {
        switch self {
        case .priceLowToHigh: return "Low to high"
        case .priceHighToLow: return "High to low"
        case .name: return "Name"
        }
    }
}

#Preview {
    CatalogView()
        .environmentObject(AppState())
}
