import SwiftUI

// MARK: - Wishlist, Fix #4
// Checklist 1.7: GET /api/v1/wishlist with query category / status /
// sort / q, category counts, roadmap KPIs (total items, total votes,
// planned count, available count), my voted ids and my notify-me ids;
// POST /api/v1/wishlist/vote, POST /api/v1/wishlist/notify (toggle),
// POST /api/v1/wishlist/submit (new item).
// No NavigationStack here: this view is pushed from Settings, so it
// uses the parent stack. No emojis, SF Symbols only.

struct WishlistRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [WshItem] = []
    @State private var categoryCounts: [String: Int] = [:]
    @State private var kpis: WshKPIs?
    @State private var myVotedIds: Set<Int> = []
    @State private var myNotifyIds: Set<Int> = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?

    @State private var selectedCategory = "All"
    @State private var selectedStatus = "all"
    @State private var selectedSort = "votes"
    @State private var searchText = ""

    @State private var submitTitle = ""
    @State private var submitDescription = ""
    @State private var submitCategory = "AI Tools"
    @State private var isSubmitting = false

    private let categories = ["All", "AI Tools", "Streaming", "Productivity", "Developer", "Design", "Security"]
    private let statuses = ["all", "suggested", "planned", "available"]
    private let sorts = [("votes", "Most voted"), ("newest", "Newest"), ("price_asc", "Lowest price")]

    var body: some View {
        List {
            Section("Roadmap") {
                HStack(spacing: 12) {
                    wshKPI(value: "\(kpis?.total_items ?? 0)", label: "Items")
                    wshKPI(value: "\(kpis?.total_votes ?? 0)", label: "Votes")
                    wshKPI(value: "\(kpis?.planned_count ?? 0)", label: "Planned")
                    wshKPI(value: "\(kpis?.available_count ?? 0)", label: "Available")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                TextField("Search the wishlist", text: $searchText)
                    .psTextField()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search the wishlist")
                    .onSubmit { Task { await load() } }
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(categoryCountLabel(category)).tag(category)
                    }
                }
                .accessibilityLabel("Wishlist category filter")
                .onChange(of: selectedCategory) { _, _ in Task { await load() } }
                Picker("Status", selection: $selectedStatus) {
                    ForEach(statuses, id: \.self) { status in
                        Text(status == "all" ? "All statuses" : status.capitalized).tag(status)
                    }
                }
                .accessibilityLabel("Wishlist status filter")
                .onChange(of: selectedStatus) { _, _ in Task { await load() } }
                Picker("Sort", selection: $selectedSort) {
                    ForEach(sorts, id: \.0) { sort in
                        Text(sort.1).tag(sort.0)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Wishlist sort order")
                .onChange(of: selectedSort) { _, _ in Task { await load() } }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && items.isEmpty {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if items.isEmpty {
                PSEmptyState(
                    systemImage: "star",
                    title: "Nothing on the wishlist",
                    body: "Try a different filter or search, or suggest a platform below."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Wishlist") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                    .font(.psHeadline)
                                Spacer()
                                if let status = item.status {
                                    PSStatusPill(
                                        text: status,
                                        systemImage: "flag.fill",
                                        tint: status == "available" ? .psSuccess : .psAmber
                                    )
                                }
                            }
                            if let description = item.description, !description.isEmpty {
                                Text(description)
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                            }
                            HStack(spacing: 12) {
                                if let category = item.category {
                                    Label(category, systemImage: "tag.fill")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                if let price = item.price {
                                    Text("KES \(price)")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                Label("\(item.votes ?? 0) votes", systemImage: "hand.thumbsup.fill")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            HStack(spacing: 10) {
                                Button {
                                    Task { await vote(item) }
                                } label: {
                                    Label(
                                        myVotedIds.contains(item.id ?? -1) ? "Voted" : "Vote",
                                        systemImage: myVotedIds.contains(item.id ?? -1) ? "hand.thumbsup.fill" : "hand.thumbsup"
                                    )
                                    .font(.psCaption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                                .disabled(!appState.isLoggedIn)
                                .accessibilityLabel("Vote for \(item.title)")
                                Button {
                                    Task { await toggleNotify(item) }
                                } label: {
                                    Label(
                                        myNotifyIds.contains(item.id ?? -1) ? "Notify me on" : "Notify me",
                                        systemImage: myNotifyIds.contains(item.id ?? -1) ? "bell.fill" : "bell"
                                    )
                                    .font(.psCaption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!appState.isLoggedIn)
                                .accessibilityLabel("Notify me about \(item.title)")
                            }
                        }
                        .psTouchTarget()
                    }
                }
            }

            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }

            Section {
                TextField("Platform or feature title", text: $submitTitle)
                    .psTextField()
                    .accessibilityLabel("Wishlist item title")
                TextField("Short description", text: $submitDescription, axis: .vertical)
                    .psTextField()
                    .lineLimit(3...)
                    .accessibilityLabel("Wishlist item description")
                Picker("Category", selection: $submitCategory) {
                    ForEach(categories.filter { $0 != "All" }, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .accessibilityLabel("New wishlist item category")
                Button {
                    Task { await submitItem() }
                } label: {
                    if isSubmitting { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Suggest for the wishlist", systemImage: "plus.circle.fill") }
                }
                .psPrimary()
                .disabled(isSubmitting || !appState.isLoggedIn)
                if !appState.isLoggedIn {
                    Text("Sign in to vote, follow items and suggest new ones.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Suggest something new")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func categoryCountLabel(_ category: String) -> String {
        guard category != "All" else { return "All" }
        if let count = categoryCounts[category] {
            return "\(category) (\(count))"
        }
        return category
    }

    private func wshKPI(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.psHeadline)
                .foregroundStyle(.psCyan)
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        var query: [String] = []
        if selectedCategory != "All" { query.append("category=\(selectedCategory)") }
        if selectedStatus != "all" { query.append("status=\(selectedStatus)") }
        query.append("sort=\(selectedSort)")
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { query.append("q=\(q)") }
        let path = "api/v1/wishlist?" + query.joined(separator: "&")
        do {
            let response: WshResponse = try await APIClient.shared.fetchJSON(path)
            items = response.items
            categoryCounts = response.category_counts ?? [:]
            kpis = response.kpis
            myVotedIds = Set(response.my_voted_ids ?? [])
            myNotifyIds = Set(response.my_notify_ids ?? [])
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func vote(_ item: WshItem) async {
        guard let id = item.id else { return }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/wishlist/vote", method: "POST", body: ["item_id": id])
            myVotedIds.insert(id)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func toggleNotify(_ item: WshItem) async {
        guard let id = item.id else { return }
        do {
            struct NotifyResponse: Decodable { let ok: Bool; let notify_me: Bool? }
            let response: NotifyResponse = try await APIClient.shared.fetchJSON(
                "api/v1/wishlist/notify", method: "POST", body: ["item_id": id])
            if response.notify_me == true {
                myNotifyIds.insert(id)
            } else {
                myNotifyIds.remove(id)
            }
            actionMessage = response.notify_me == true
                ? "You will be notified about \(item.title)."
                : "Notifications off for \(item.title)."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func submitItem() async {
        let title = submitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            actionMessage = "Give the wishlist item a title."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/wishlist/submit", method: "POST",
                body: ["title": title,
                       "description": submitDescription,
                       "category": submitCategory])
            actionMessage = "Thanks. Your suggestion was added to the wishlist."
            submitTitle = ""
            submitDescription = ""
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Wishlist response types (keys from backend/api_v1.py)

struct WshItem: Decodable, Identifiable {
    let id: Int?
    let title: String
    let description: String?
    let category: String?
    let status: String?
    let votes: Int?
    let price: Int?
}

struct WshKPIs: Decodable {
    let total_items: Int?
    let total_votes: Int?
    let planned_count: Int?
    let available_count: Int?
}

struct WshResponse: Decodable {
    let ok: Bool
    let items: [WshItem]
    let category_counts: [String: Int]?
    let kpis: WshKPIs?
    let my_voted_ids: [Int]?
    let my_notify_ids: [Int]?
}

#Preview {
    NavigationStack {
        WishlistRootView()
            .environmentObject(AppState())
    }
}
