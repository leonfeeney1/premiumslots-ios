import SwiftUI

// MARK: - Help centre, blog, privacy, terms and receipts, Fix #4
// Checklist 1.8: GET /api/v1/help (search q, category filter) and
// GET /api/v1/help/<slug>; GET /api/v1/blog and GET /api/v1/blog/<slug>
// with related posts; privacy and terms as in-app text screens; receipts
// as PDF via GET /api/v1/receipts/<id> with a share sheet, plus verify
// via GET /api/v1/receipts/verify?payload=&signature=.
// No NavigationStack here: these views are pushed from Settings, so
// they use the parent stack. No emojis, SF Symbols only.

// MARK: - Shared helpers for the content screens
// Percent-encoding for query values: APIClient builds the URL from a
// raw path string, so a value with a space (for example the "AI Tools"
// category) produced an invalid URL and the request failed before it
// reached the server. Every query value in these files goes through
// psEncodedQuery.

func psEncodedQuery(_ params: [(String, String)]) -> String {
    // urlQueryAllowed still permits & and =, which would split a
    // value into extra parameters, so those are excluded too.
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&="))
    return params.map { key, value in
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(key)=\(encoded)"
    }.joined(separator: "&")
}

/// Renders server markdown (help articles and blog posts store their
/// body as markdown) as styled text, falling back to the raw string
/// when parsing fails.
func psStyledMarkdown(_ text: String) -> Text {
    if let styled = try? AttributedString(markdown: text) {
        return Text(styled)
    }
    return Text(text)
}

// MARK: - Help centre

struct HelpRootView: View {
    @State private var articles: [HelpArticle] = []
    @State private var serverCategories: [String] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchTask: Task<Void, Never>?

    // The server returns the distinct published categories with the
    // list. Deriving them from the loaded page is wrong: once a
    // search or a filter narrows the page, the other categories
    // vanish from the chips. Fall back to the loaded articles only
    // until the first list response arrives.
    private var categories: [String] {
        if !serverCategories.isEmpty { return ["All"] + serverCategories }
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

    // FAQ answers: articles filed under the FAQ category, if the
    // site has any. There is no separate FAQ endpoint on the server,
    // so when no FAQ-category article exists the four real questions
    // from the site help pages are shown instead.
    private var faqArticles: [HelpArticle] {
        articles.filter { ($0.category ?? "").lowercased() == "faq" }
    }

    private let fallbackFAQs: [(String, String)] = [
        ("How do I pay?", "Send the exact amount by M-PESA to PayBill 400200, account 1192526, then submit the 10-letter-and-number code from your confirmation message in checkout."),
        ("When do I get my details?", "Once the team verifies your code, your slot moves to Active in My Slots and your vault details appear there."),
        ("Can I use my slot on more than one device?", "No. 1 slot = 1 device. Use it on your own device only."),
        ("What if my code is rejected?", "Check the code is exactly 10 letters and numbers and has not been used before, then try again or report the issue from My Slots."),
    ]

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
                    ForEach(filteredArticles, id: \.rowID) { article in
                        NavigationLink {
                            HelpArticleDetailView(slug: article.slug ?? "")
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(article.title)
                                    .font(.psHeadline)
                                if let excerpt = article.excerpt, !excerpt.isEmpty {
                                    Text(excerpt)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    if let category = article.category {
                                        Text(category)
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                    if let updated = article.updated_at {
                                        Text(psShortDate(updated))
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                }
                            }
                        }
                        .accessibilityLabel("Help article: \(article.title)")
                    }
                }
            }

            Section("Frequently asked questions") {
                if !faqArticles.isEmpty {
                    ForEach(faqArticles, id: \.rowID) { article in
                        DisclosureGroup(article.title) {
                            if let body = article.bodyText, !body.isEmpty {
                                psStyledMarkdown(body)
                                    .font(.psBody)
                                    .foregroundStyle(.psDim)
                            }
                        }
                        .font(.psHeadline)
                    }
                } else {
                    ForEach(fallbackFAQs, id: \.0) { faq in
                        DisclosureGroup(faq.0) {
                            Text(faq.1)
                                .font(.psBody)
                                .foregroundStyle(.psDim)
                        }
                        .font(.psHeadline)
                    }
                }
            }

            Section {
                NavigationLink {
                    TicketsRootView()
                } label: {
                    Label("Still need help? Send a ticket", systemImage: "envelope.fill")
                        .font(.psBody)
                }
                .accessibilityLabel("Still need help? Send a ticket")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Help centre")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: searchText) { _, _ in
            // Debounced search: loading on every keystroke fired a
            // request per character and let slow responses overwrite
            // newer ones. Wait briefly for typing to settle.
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await load()
            }
        }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        var params: [(String, String)] = []
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { params.append(("q", q)) }
        if selectedCategory != "All" { params.append(("category", selectedCategory)) }
        let path = params.isEmpty ? "api/v1/help" : "api/v1/help?" + psEncodedQuery(params)
        do {
            let response: HelpListResponse = try await APIClient.shared.fetchJSON(path)
            articles = response.articles
            if let server = response.categories, !server.isEmpty {
                serverCategories = server
            }
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
                    if let updated = article.updated_at {
                        Text("Updated \(psShortDate(updated))")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    if let excerpt = article.excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    // The article body is the "markdown" column on the
                    // server, not "content". Reading content only left
                    // this screen blank even though the request
                    // succeeded. bodyText prefers markdown and falls
                    // back to content for older rows.
                    if let body = article.bodyText, !body.isEmpty {
                        psStyledMarkdown(body)
                            .font(.psBody)
                            .foregroundStyle(.psDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
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
        .scrollIndicators(.hidden)
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
                            HStack(alignment: .top, spacing: 12) {
                                if let coverURL = post.coverURL {
                                    AsyncImage(url: coverURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.psSurface
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(post.title)
                                        .font(.psHeadline)
                                    if let excerpt = post.excerpt ?? post.content {
                                        Text(excerpt)
                                            .font(.psBody)
                                            .foregroundStyle(.psMuted)
                                            .lineLimit(2)
                                    }
                                    HStack(spacing: 8) {
                                        if let author = post.author, !author.isEmpty {
                                            Text(author)
                                                .font(.psCaption)
                                                .foregroundStyle(.psMuted)
                                        }
                                        if let date = post.displayDate {
                                            Text(psShortDate(date))
                                                .font(.psCaption)
                                                .foregroundStyle(.psMuted)
                                        }
                                    }
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
        .scrollIndicators(.hidden)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let loadError {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                } else if isLoading && post == nil {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .padding(.top, 32)
                } else if let post {
                    if let coverURL = post.coverURL {
                        AsyncImage(url: coverURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.psSurface
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Cover image for \(post.title)")
                    }
                    Text(post.title)
                        .font(.psTitle)
                    HStack(spacing: 8) {
                        if let author = post.author, !author.isEmpty {
                            Text(author)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if let date = post.displayDate {
                            Text(psShortDate(date))
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    // Full body, no truncation: the old detail was a
                    // List whose single cell cut long articles short,
                    // and it read only "content" while the server
                    // also serves the body as "markdown". A plain
                    // ScrollView with an unclipped Text renders the
                    // whole article, and bodyText prefers markdown
                    // with content as the fallback.
                    if let body = post.bodyText, !body.isEmpty {
                        psStyledMarkdown(body)
                            .font(.psBody)
                            .foregroundStyle(.psDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    } else if let excerpt = post.excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.psBody)
                            .foregroundStyle(.psDim)
                    }

                    if !related.isEmpty {
                        Text("Related posts")
                            .font(.psHeadline)
                            .padding(.top, 8)
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
                } else {
                    PSEmptyState(
                        systemImage: "newspaper",
                        title: "Post not found",
                        body: "This blog post is no longer available."
                    )
                }
            }
            .psScreenPadding()
        }
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
                "api/v1/receipts/verify?" + psEncodedQuery([("payload", payload), ("signature", signature)]))
            verifyResult = response
        } catch {
            verifyMessage = error.localizedDescription
        }
    }
}

// MARK: - Help and blog response types (keys from backend/api_v1.py)
// Help list rows carry slug, title, excerpt, category, updated_at
// and NO id, so rows are identified by slug. The article body is
// the "markdown" column; "content" is kept as a fallback for rows
// that carry it. Blog list rows carry cover_image and published_at
// (not created_at); the detail body is "content" with "markdown" as
// the fallback.

struct HelpArticle: Decodable, Identifiable {
    let id: Int?
    let title: String
    let slug: String?
    let content: String?
    let markdown: String?
    let excerpt: String?
    let category: String?
    let updated_at: String?

    // The list endpoint returns no id, so every article decoded with
    // id nil. Using id for ForEach identity collapsed the list.
    var rowID: String { slug ?? title }
    var bodyText: String? { markdown ?? content }
}

struct HelpListResponse: Decodable {
    let ok: Bool
    let articles: [HelpArticle]
    let categories: [String]?
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
    let markdown: String?
    let excerpt: String?
    let author: String?
    let cover_image: String?
    let published_at: String?
    let created_at: String?

    var bodyText: String? { markdown ?? content }
    var displayDate: String? { published_at ?? created_at }
    var coverURL: URL? {
        guard let cover_image, !cover_image.isEmpty else { return nil }
        if let url = URL(string: cover_image), url.scheme != nil { return url }
        let path = cover_image.hasPrefix("/") ? String(cover_image.dropFirst()) : cover_image
        return URL(string: "https://premiumslots.tech/" + path)
    }
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
