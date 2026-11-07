import SwiftUI

// MARK: - Help centre, blog, privacy, terms and receipts, Fix #4
// Checklist 1.8: GET /api/v1/help (search q, category filter) and
// GET /api/v1/help/<slug>; GET /api/v1/blog and GET /api/v1/blog/<slug>
// with related posts; privacy and terms as in-app text screens; receipts
// as PDF via GET /api/v1/receipts/<id> with a share sheet, plus verify
// via GET /api/v1/receipts/verify?payload=&signature=.
// No NavigationStack here: these views are pushed from Settings, so
// they use the parent stack. No emojis, SF Symbols only.

// MARK: - Help centre

struct HelpRootView: View {
    @State private var articles: [HelpArticle] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var isLoading = false
    @State private var loadError: String?

    private var categories: [String] {
        var seen = ["All"]
        for article in articles {
            if let category = article.category, !category.isEmpty, !seen.contains(category) {
                seen.append(category)
            }
        }
        return seen
    }

    private var filteredArticles: [HelpArticle] {
        guard selectedCategory != "All" else { return articles }
        return articles.filter { $0.category == selectedCategory }
    }

    var body: some View {
        List {
            Section {
                TextField("Search help articles", text: $searchText)
                    .psTextField()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search help articles")
                    .onSubmit { Task { await load() } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button(category) {
                                selectedCategory = category
                                Task { await load() }
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedCategory == category ? .psCyan : .psMuted)
                            .accessibilityLabel("Filter by \(category)")
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && articles.isEmpty {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if filteredArticles.isEmpty {
                PSEmptyState(
                    systemImage: "questionmark.circle",
                    title: "No articles found",
                    body: "Try a different search or category. For a slot problem, include the platform name and your M-PESA code when you contact support."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Articles") {
                    ForEach(filteredArticles) { article in
                        NavigationLink {
                            HelpArticleDetailView(slug: article.slug ?? "")
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(article.title)
                                    .font(.psHeadline)
                                if let category = article.category {
                                    Text(category)
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                        }
                        .accessibilityLabel("Help article: \(article.title)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Help centre")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: searchText) { _, _ in
            Task { await load() }
        }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        var path = "api/v1/help"
        var query: [String] = []
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { query.append("q=\(q)") }
        if selectedCategory != "All" { query.append("category=\(selectedCategory)") }
        if !query.isEmpty { path += "?" + query.joined(separator: "&") }
        do {
            let response: HelpListResponse = try await APIClient.shared.fetchJSON(path)
            articles = response.articles
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct HelpArticleDetailView: View {
    let slug: String
    @State private var article: HelpArticle?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let loadError {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                } else if isLoading && article == nil {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .padding(.top, 32)
                } else if let article {
                    Text(article.title)
                        .font(.psTitle)
                    if let category = article.category {
                        PSStatusPill(text: category, systemImage: "tag.fill", tint: .psCyan)
                    }
                    Text(article.content ?? "")
                        .font(.psBody)
                        .foregroundStyle(.psDim)
                } else {
                    PSEmptyState(
                        systemImage: "questionmark.circle",
                        title: "Article not found",
                        body: "This help article is no longer available."
                    )
                }
            }
            .psScreenPadding()
        }
        .background(Color.psBackground)
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard !slug.isEmpty else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: HelpArticleResponse = try await APIClient.shared.fetchJSON("api/v1/help/\(slug)")
            article = response.article
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Blog

struct BlogRootView: View {
    @State private var posts: [BlogPost] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && posts.isEmpty {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if posts.isEmpty {
                PSEmptyState(
                    systemImage: "newspaper",
                    title: "No posts yet",
                    body: "Blog posts from premiumslots.tech will appear here."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Latest posts") {
                    ForEach(posts) { post in
                        NavigationLink {
                            BlogPostDetailView(slug: post.slug ?? "")
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(post.title)
                                    .font(.psHeadline)
                                if let excerpt = post.excerpt ?? post.content {
                                    Text(excerpt)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                        .lineLimit(2)
                                }
                                if let date = post.created_at {
                                    Text(date)
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                        }
                        .accessibilityLabel("Blog post: \(post.title)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Blog")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: BlogListResponse = try await APIClient.shared.fetchJSON("api/v1/blog")
            posts = response.posts
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct BlogPostDetailView: View {
    let slug: String
    @State private var post: BlogPost?
    @State private var related: [BlogPost] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && post == nil {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let post {
                Section {
                    Text(post.title)
                        .font(.psTitle)
                    if let date = post.created_at {
                        Text(date)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    Text(post.content ?? post.excerpt ?? "")
                        .font(.psBody)
                        .foregroundStyle(.psDim)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !related.isEmpty {
                    Section("Related posts") {
                        ForEach(related) { item in
                            NavigationLink {
                                BlogPostDetailView(slug: item.slug ?? "")
                            } label: {
                                Text(item.title)
                                    .font(.psBody)
                            }
                            .accessibilityLabel("Related post: \(item.title)")
                        }
                    }
                }
            } else {
                PSEmptyState(
                    systemImage: "newspaper",
                    title: "Post not found",
                    body: "This blog post is no longer available."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        guard !slug.isEmpty else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: BlogPostResponse = try await APIClient.shared.fetchJSON("api/v1/blog/\(slug)")
            post = response.post
            related = response.related ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Privacy and terms (static in-app text screens)
// The full privacy policy and terms of service live on
// premiumslots.tech. These screens state that plainly and link out,
// with only a short summary of what the pages cover. Account
// authentication is handled by the identity provider Clerk, and
// administrators cannot see your password.

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy policy")
                    .font(.psTitle)
                Text("The full privacy policy lives on premiumslots.tech. It covers what data PremiumSlots collects, how it is used, and your rights over it.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Text("In short: your account, payment confirmations and slot details are used to deliver the slots you buy. Account authentication (passwords, social logins and secure sessions) is handled by our identity provider Clerk. Our administrators cannot see your password.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Link("Read the full privacy policy on premiumslots.tech", destination: URL(string: "https://premiumslots.tech/privacy")!)
                    .font(.psBody)
                    .accessibilityLabel("Read the full privacy policy on premiumslots.tech")
            }
            .psScreenPadding()
        }
        .background(Color.psBackground)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Terms of service")
                    .font(.psTitle)
                Text("The full terms of service live on premiumslots.tech. They cover how slots are sold, delivered and renewed, and what is expected of you as a customer.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Text("In short: 1 slot = 1 device. Never change the account password or email on a delivered slot. Slots are verified by M-PESA code and delivered through the encrypted vault.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Link("Read the full terms of service on premiumslots.tech", destination: URL(string: "https://premiumslots.tech/terms")!)
                    .font(.psBody)
                    .accessibilityLabel("Read the full terms of service on premiumslots.tech")
            }
            .psScreenPadding()
        }
        .background(Color.psBackground)
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Receipts

struct ReceiptsView: View {
    @State private var receiptIdText = ""
    @State private var pdfURL: URL?
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var verifyPayload = ""
    @State private var verifySignature = ""
    @State private var verifyResult: ReceiptVerifyResponse?
    @State private var verifyMessage: String?
    @State private var isVerifying = false

    var body: some View {
        List {
            Section {
                Text("Enter the order number from My Slots to download its receipt as a PDF.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                TextField("Order number, for example 12", text: $receiptIdText)
                    .psTextField()
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Receipt order number")
                Button {
                    Task { await downloadReceipt() }
                } label: {
                    if isDownloading { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Download receipt PDF", systemImage: "arrow.down.doc.fill") }
                }
                .psPrimary()
                .disabled(isDownloading)
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share receipt PDF", systemImage: "square.and.arrow.up")
                            .font(.psBody)
                    }
                    .accessibilityLabel("Share receipt PDF")
                }
                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Download a receipt")
            }

            Section {
                Text("Paste the payload and signature printed on a receipt to check it is genuine.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                TextField("Payload, for example receipt:12", text: $verifyPayload)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Receipt payload")
                TextField("Signature", text: $verifySignature)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Receipt signature")
                Button {
                    Task { await verifyReceipt() }
                } label: {
                    if isVerifying { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Verify receipt", systemImage: "checkmark.seal.fill") }
                }
                .psPrimary()
                .disabled(isVerifying)
                if let verifyResult {
                    HStack {
                        Image(systemName: verifyResult.verified == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(verifyResult.verified == true ? .psSuccess : .psDanger)
                            .accessibilityHidden(true)
                        Text(verifyResult.verified == true ? "Receipt verified." : "Receipt could not be verified.")
                            .font(.psHeadline)
                    }
                    if let method = verifyResult.method {
                        Text("Check: \(method)")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    if let note = verifyResult.note {
                        Text(note)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                if let verifyMessage {
                    Text(verifyMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Verify a receipt")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 8)
    }

    private func downloadReceipt() async {
        guard let id = Int(receiptIdText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            downloadMessage = "Enter the order number first."
            return
        }
        isDownloading = true
        downloadMessage = nil
        pdfURL = nil
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/receipts/\(id)")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("receipt-\(id).pdf")
            try data.write(to: url, options: .atomic)
            pdfURL = url
            downloadMessage = "Receipt PDF is ready to share."
        } catch {
            downloadMessage = error.localizedDescription
        }
    }

    private func verifyReceipt() async {
        let payload = verifyPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            verifyMessage = "Enter the payload first."
            return
        }
        isVerifying = true
        verifyMessage = nil
        verifyResult = nil
        defer { isVerifying = false }
        let signature = verifySignature.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response: ReceiptVerifyResponse = try await APIClient.shared.fetchJSON(
                "api/v1/receipts/verify?payload=\(payload)&signature=\(signature)")
            verifyResult = response
        } catch {
            verifyMessage = error.localizedDescription
        }
    }
}

// MARK: - Help and blog response types (keys from backend/api_v1.py)

struct HelpArticle: Decodable, Identifiable {
    let id: Int?
    let title: String
    let slug: String?
    let content: String?
    let category: String?
    let created_at: String?
}

struct HelpListResponse: Decodable {
    let ok: Bool
    let articles: [HelpArticle]
}

struct HelpArticleResponse: Decodable {
    let ok: Bool
    let article: HelpArticle
}

struct BlogPost: Decodable, Identifiable {
    let id: Int?
    let title: String
    let slug: String?
    let content: String?
    let excerpt: String?
    let created_at: String?
}

struct BlogListResponse: Decodable {
    let ok: Bool
    let posts: [BlogPost]
}

struct BlogPostResponse: Decodable {
    let ok: Bool
    let post: BlogPost
    let related: [BlogPost]?
}

struct ReceiptVerifyResponse: Decodable {
    let ok: Bool
    let verified: Bool?
    let payload: String?
    let method: String?
    let note: String?
}

#Preview {
    NavigationStack {
        HelpRootView()
    }
}
