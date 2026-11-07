import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedPlatform: Platform?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchAndFilters
                    if let message = appState.refreshMessage {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.psSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
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
                .padding()
            }
            .background(Color.psObsidian)
            .navigationTitle("PremiumSlots")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshLiveTotal() }
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
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ShieldLogoView(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared subscriptions,")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("one slot at a time.")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.psCyan)
                if let total = appState.liveTotalSlots {
                    Text("\(Platform.bundled.count) platforms · \(total) slots in rotation")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Spacer()
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 10) {
            HStack {
                Toggle("Available only", isOn: $appState.showAvailableOnly)
                    .toggleStyle(.switch)
                    .tint(.psCyan)
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
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
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
            Text("Stock last verified \(Platform.stockVerifiedDate). Homepage checked \(Platform.homepageCheckedDate): \(Platform.liveTotalSlotsOnHomepage) slots in rotation, \(Platform.communitySuggestions) community suggestions.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
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
