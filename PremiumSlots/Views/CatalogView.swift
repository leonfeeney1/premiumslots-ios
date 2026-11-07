import SwiftUI

// MARK: - Catalogue, v4 (v6: second design pass)
// Modern shopping layout: clean search bar at the top, filter chips
// (All / Available / Sold out) with live counts, a sort menu, and
// platform cards in a 2-column grid. Live data from the catalogue
// API on launch and on pull-to-refresh only: there is no reload
// button anywhere on this screen. While loading for the first
// time, skeleton cards show immediately; a refresh keeps the
// current grid on screen. On failure an error state with retry
// shows only when there is nothing to show, and a failed refresh
// with a grid on screen shows a small retry banner instead.
// Tap a card to open the platform detail as a native sheet with
// detents. Stock states are honest: sold out, low stock
// (5 or fewer left) and plenty of stock each read differently on
// the card, and the detail sheet repeats them.

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

    /// True only on the very first load, before any catalogue
    /// (live or saved) has ever been shown.
    private var isFirstLoad: Bool {
        isLoading && appState.liveState == .unknown
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    searchBar
                    filterRow
                    if let loadError, appState.platforms.isEmpty {
                        PSErrorState(message: loadError) {
                            Task { await load() }
                        }
                    } else {
                        content
                    }
                }
                .padding(16)
            }
            .psHiddenScrollIndicators()
            .scrollDismissesKeyboard(.interactively)
            .psScreenBackground()
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                dismissKeyboardButton
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
        // refreshCatalogue never throws: on failure it keeps the
        // saved catalogue and marks the state offline, so a failed
        // refresh leaves the grid in place.
        await appState.refreshCatalogue()
        if appState.liveState == .live {
            loadError = nil
        } else if appState.platforms.isEmpty {
            loadError = "The latest catalogue could not be loaded. Check your connection and try again."
        } else {
            loadError = nil
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
        case .mostStock:
            list.sort { $0.slotsLeft > $1.slotsLeft }
        }
        return list
    }

    private var availableCount: Int {
        appState.platforms.filter { !$0.isSoldOut }.count
    }

    private var soldOutCount: Int {
        appState.platforms.filter { $0.isSoldOut }.count
    }

    private func count(for option: CatalogFilter) -> Int {
        switch option {
        case .all: return appState.platforms.count
        case .available: return availableCount
        case .soldOut: return soldOutCount
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LogoLockupView(height: 32)
                Spacer()
                if appState.liveState == .live {
                    PSStatusPill(text: "Live", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                } else if appState.liveState == .offline {
                    PSStatusPill(text: "Saved catalogue", systemImage: "wifi.slash", tint: .psMuted)
                }
            }
            Text("Shared subscriptions, one slot at a time.")
                .font(.psTitle)
            if appState.liveState == .live, let total = appState.liveTotalSlots {
                Text("\(appState.platformCount) platforms · \(total) slots in rotation · \(availableCount) available now")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            } else if !appState.platforms.isEmpty {
                Text("\(appState.platformCount) platforms · \(availableCount) available now")
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
                            Text("\(option.label) (\(count(for: option)))")
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
                        .accessibilityLabel("Show \(option.label.lowercased()) platforms, \(count(for: option))")
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
        if isFirstLoad {
            PSSkeletonGrid(count: 6)
        } else {
            if let loadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.psWarning)
                        .accessibilityHidden(true)
                    Text("Showing the saved catalogue. The latest list could not be loaded.")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    Spacer()
                    Button("Retry") {
                        Task { await load() }
                    }
                    .psTextStyle(.caption)
                }
                .padding(10)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("\(filteredPlatforms.count) platform\(filteredPlatforms.count == 1 ? "" : "s")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
                .accessibilityLabel("\(filteredPlatforms.count) platforms shown")
            if filteredPlatforms.isEmpty {
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
    case mostStock

    var label: String {
        switch self {
        case .priceLowToHigh: return "Price: low to high"
        case .priceHighToLow: return "Price: high to low"
        case .name: return "Name: A to Z"
        case .mostStock: return "Most slots left"
        }
    }

    var shortLabel: String {
        switch self {
        case .priceLowToHigh: return "Low to high"
        case .priceHighToLow: return "High to low"
        case .name: return "Name"
        case .mostStock: return "Most stock"
        }
    }
}

#Preview {
    CatalogView()
        .environmentObject(AppState())
}
