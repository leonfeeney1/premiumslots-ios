import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedPlatform: Platform?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    liveBanner
                    searchAndFilters
                    if appState.filteredPlatforms.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.filteredPlatforms) { platform in
                            Button {
                                selectedPlatform = platform
                            } label: {
                                SlotCard(platform: platform)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    stockNote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshCatalogue() }
                    } label: {
                        if appState.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(appState.isRefreshing)
                }
            }
            .sheet(item: $selectedPlatform) { platform in
                PlatformDetailView(platform: platform)
            }
            .searchable(text: $appState.searchText, prompt: "Search platforms")
            .task { await appState.refreshCatalogue() }
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
        }
    }

    private var liveBanner: some View {
        Group {
            switch appState.liveState {
            case .live:
                Label("Live catalogue from premiumslots.tech",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .offline:
                Label("Offline: using saved catalogue from \(Platform.stockVerifiedDate)",
                      systemImage: "wifi.slash")
                    .foregroundStyle(.psAmber)
            case .unknown:
                Label("Checking live catalogue…", systemImage: "arrow.clockwise")
                    .foregroundStyle(.psMuted)
            }
        }
        .font(.psCaption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.psMuted)
            Text("No platforms match your search.")
                .font(.psHeadline)
            Text("Try a different name, or clear the available-only filter.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
