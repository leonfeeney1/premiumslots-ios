import SwiftUI

// MARK: - Catalogue, v3 Fix #3
// HIG overhaul: inset-grouped List, pull-to-refresh, native sheet
// with detents for the platform detail, shared empty/error states,
// 16pt screen padding, 44pt touch targets, VoiceOver labels on
// icon buttons. The list rows are the SlotCard content in a plain
// row; section headers carry the live/offline state.

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedPlatform: Platform?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    liveBanner
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                }

                Section {
                    if isLoading && appState.platforms == Platform.bundled {
                        HStack {
                            Spacer()
                            PSRingSpinner(diameter: 24, lineWidth: 2)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } else if let loadError {
                        PSErrorState(message: loadError) {
                            Task { await load() }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if appState.filteredPlatforms.isEmpty {
                        PSEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No platforms match your search.",
                            body: "Try a different name, or clear the available-only filter."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(appState.filteredPlatforms) { platform in
                            Button {
                                selectedPlatform = platform
                            } label: {
                                SlotCard(platform: platform)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(platform.name), \(platform.formattedPrice), \(platform.isSoldOut ? "sold out" : "\(platform.slotsLeft) slots left")")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                } header: {
                    Text("Platforms")
                }

                Section {
                    stockNote
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.psBackground)
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .searchable(text: $appState.searchText, prompt: "Search platforms")
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
        if appState.liveState == .offline && appState.platforms == Platform.bundled {
            loadError = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LogoLockupView(height: 32)
            Text("Shared subscriptions, one slot at a time.")
                .font(.psTitle)
            if let total = appState.liveTotalSlots {
                Text("\(appState.platformCount) platforms · \(total) slots in rotation")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            searchAndFilters
                .padding(.top, 4)
        }
    }

    private var liveBanner: some View {
        Group {
            switch appState.liveState {
            case .live:
                PSLiveBanner(message: "Live catalogue from premiumslots.tech")
            case .offline:
                PSOfflineBanner(message: "Offline: using saved catalogue from \(Platform.stockVerifiedDate)")
            case .unknown:
                Label("Checking live catalogue…", systemImage: "arrow.clockwise")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var searchAndFilters: some View {
        HStack {
            Toggle("Available only", isOn: $appState.showAvailableOnly)
                .toggleStyle(.switch)
                .tint(.psCyan)
                .font(.psBody)
            Spacer()
            Button {
                appState.sortByPriceAscending.toggle()
            } label: {
                Label(
                    appState.sortByPriceAscending ? "Price: low to high" : "Price: high to low",
                    systemImage: "arrow.up.arrow.down"
                )
                .font(.psCaption)
            }
            .accessibilityLabel(appState.sortByPriceAscending ? "Sort by price, low to high" : "Sort by price, high to low")
        }
    }

    private var stockNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.liveState != .live {
                Text("Stock last verified \(Platform.stockVerifiedDate). Homepage checked \(Platform.homepageCheckedDate): \(Platform.liveTotalSlotsOnHomepage) slots in rotation, \(Platform.communitySuggestions) community suggestions.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Text("1 slot = 1 device. Prices are in Kenyan shillings.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
    }
}

#Preview {
    CatalogView()
        .environmentObject(AppState())
}
