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
    @State private var serverCategories: [String] = []
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
    @State private var submitPrice = ""
    @State private var isSubmitting = false

    // Server categories when the list response carries them; the
    // hardcoded list is the fallback only. Statuses include
    // under_review: new suggestions are filed under that status by
    // the server, so "suggested" alone never matched them.
    private var categories: [String] {
        serverCategories.isEmpty
            ? ["All", "AI Tools", "Streaming", "Productivity", "Developer", "Design", "Security"]
            : ["All"] + serverCategories
    }
    private let statuses = ["all", "suggested", "under_review", "planned", "available"]
    private let sorts = [("votes", "Most voted"), ("newest", "Newest"), ("price_asc", "Lowest price")]

    var body: some View {
        List {
            Section("Roadmap") {
                HStack(spacing: 12) {
                    wshKPI(value: kpis.map { "\($0.total_items ?? 0)" } ?? "–", label: "Items")
                    wshKPI(value: kpis.map { "\($0.total_votes ?? 0)" } ?? "–", label: "Votes")
                    wshKPI(value: kpis.map { "\($0.planned_count ?? 0)" } ?? "–", label: "Planned")
                    wshKPI(value: kpis.map { "\($0.available_count ?? 0)" } ?? "–", label: "Available")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !appState.isLoggedIn {
                Section {
                    Text("Sign in to see the wishlist, vote and suggest new platforms.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
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
                        HStack(alignment: .top, spacing: 12) {
                            PlatformLogoView(name: item.title, size: 44)
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
                                if let price = item.price, price > 0 {
                                    Text(psKES(price))
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
                                if myVotedIds.contains(item.id ?? -1) {
                                    Button("Remove vote") {
                                        Task { await vote(item) }
                                    }
                                    .font(.psCaption)
                                    .accessibilityLabel("Remove vote for \(item.title)")
                                }
                            }
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
                TextField("Estimated price in KES, optional", text: $submitPrice)
                    .psTextField()
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Estimated price in KES")
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
        .scrollIndicators(.hidden)
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
        // The list endpoint requires a signed-in session. Without
        // this guard a signed-out visit failed with a 401 and showed
        // a raw error instead of the sign-in prompt above.
        guard appState.isLoggedIn else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        var params: [(String, String)] = []
        if selectedCategory != "All" { params.append(("category", selectedCategory)) }
        if selectedStatus != "all" { params.append(("status", selectedStatus)) }
        params.append(("sort", selectedSort))
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { params.append(("q", q)) }
        let path = "api/v1/wishlist?" + psEncodedQuery(params)
        do {
            let response: WshResponse = try await APIClient.shared.fetchJSON(path)
            items = response.items
            categoryCounts = response.category_counts ?? [:]
            if let server = response.categories, !server.isEmpty {
                serverCategories = server
            }
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
            // The server vote endpoint TOGGLES: voting again removes
            // the vote. The old code marked the item voted before the
            // call and never read the result, so removing a vote
            // showed the wrong state until the next reload. Trust the
            // returned voted flag and count instead.
            let response: WshVoteResponse = try await APIClient.shared.fetchJSON(
                "api/v1/wishlist/vote", method: "POST", body: ["item_id": id])
            if response.voted == true {
                myVotedIds.insert(id)
            } else {
                myVotedIds.remove(id)
            }
            if let index = items.firstIndex(where: { $0.id == id }),
               let count = response.votes_count {
                items[index].votes = count
            }
            actionMessage = response.voted == true
                ? "Vote counted for \(item.title)."
                : "Vote removed for \(item.title)."
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
        var body: [String: Any] = ["title": title,
                   "description": submitDescription,
                   "category": submitCategory]
        if let price = Int(submitPrice.trimmingCharacters(in: .whitespacesAndNewlines)), price > 0 {
            body["estimated_price"] = price
        }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/wishlist/submit", method: "POST", body: body)
            actionMessage = "Thanks. Your suggestion was added to the wishlist."
            submitTitle = ""
            submitDescription = ""
            submitPrice = ""
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Wishlist response types (keys from backend/api_v1.py)
// The list returns the full WishlistItems row: the vote count is
// "votes_count" and the price is "estimated_price", not "votes" and
// "price". Reading those names left every row at 0 votes with no
// price. There is no delete endpoint on the server: removing an
// item means removing your vote (the vote endpoint toggles) or
// turning its notify-me off.

struct WshItem: Decodable, Identifiable {
    let id: Int?
    let title: String
    let description: String?
    let category: String?
    let status: String?
    var votes: Int?
    var price: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, status
        case votes = "votes_count"
        case price = "estimated_price"
    }
}

struct WshVoteResponse: Decodable {
    let ok: Bool
    let action: String?
    let voted: Bool?
    let votes_count: Int?
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
    let categories: [String]?
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
