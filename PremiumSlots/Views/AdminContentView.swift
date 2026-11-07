import SwiftUI

// MARK: - Admin content, v3 Fix #4 (checklist sections 2.5-2.6)
// Coupons, blog and help articles from the live /api/v1/admin/*
// endpoints. No emojis, SF Symbols only, Theme.swift tokens only.

// MARK: - Coupons
// GET /api/v1/admin/coupons returns {"ok": true, "coupons": [rows]}.
// Create body: {"code", "discount_type": "percent"|"flat",
// "discount_value", "max_discount_amount", "min_amount",
// "max_redemptions", "max_redemptions_per_user", "customer_type",
// "service_restriction", "expires_at", "is_active"} returns
// {"coupon_id", "code"}. PUT sends the same fields.
// GET /api/v1/admin/coupons/<id>/redemptions returns
// {"redemptions": [rows]}. POST /api/v1/admin/coupons/blast with
// {"code", "user_ids"?, "subject"?, "message"?} returns
// {"code": ..., "emailed": Int}.

struct AdminCouponRow: Decodable, Identifiable, Equatable {
    let id: Int
    let code: String?
    let discount_type: String?
    let discount_value: Int?
    let value: Int?
    let max_discount_amount: Int?
    let min_amount: Int?
    let max_redemptions: Int?
    let max_redemptions_per_user: Int?
    let customer_type: String?
    let service_restriction: String?
    let expires_at: String?
    let expiry_date: String?
    let is_active: Bool?
    let active: Bool?

    var discountValue: Int { discount_value ?? value ?? 0 }
    var expiry: String? { expires_at ?? expiry_date }
    var isActive: Bool { is_active ?? active ?? true }
}

struct AdminCouponsResponse: Decodable {
    let ok: Bool
    let coupons: [AdminCouponRow]?
}

struct AdminRedemptionsResponse: Decodable {
    let ok: Bool
    let redemptions: [AdminGenericRow]?
}

struct AdminCouponsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var coupons: [AdminCouponRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var editing: AdminCouponRow?
    @State private var showCreate = false
    @State private var redemptionsFor: AdminCouponRow?
    @State private var blastFor: AdminCouponRow?
    @State private var confirmDelete: AdminCouponRow?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && coupons.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading coupons")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, coupons.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Coupons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create coupon")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) {
            AdminCouponFormSheet(coupon: nil) {
                showCreate = false
                Task { await load() }
            }
        }
        .sheet(item: $editing) { coupon in
            AdminCouponFormSheet(coupon: coupon) {
                editing = nil
                Task { await load() }
            }
        }
        .sheet(item: $redemptionsFor) { coupon in
            AdminCouponRedemptionsSheet(coupon: coupon)
        }
        .sheet(item: $blastFor) { coupon in
            AdminCouponBlastSheet(coupon: coupon)
        }
        .alert("Delete coupon?", isPresented: .constant(confirmDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let coupon = confirmDelete {
                    confirmDelete = nil
                    Task { await deleteCoupon(coupon) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Coupon \(confirmDelete?.code ?? "") will be deleted. This cannot be undone.")
        }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if coupons.isEmpty {
                    PSEmptyState(
                        systemImage: "ticket.fill",
                        title: "No coupons yet",
                        body: "Create a coupon to offer a discount at checkout."
                    )
                }
                ForEach(coupons) { coupon in
                    couponRow(coupon)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func couponRow(_ coupon: AdminCouponRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(coupon.code ?? "Coupon #\(coupon.id)")
                    .font(.psMono)
                Spacer()
                PSStatusPill(
                    text: coupon.isActive ? "Active" : "Inactive",
                    systemImage: coupon.isActive ? "checkmark.circle.fill" : "pause.circle.fill",
                    tint: coupon.isActive ? .psSuccess : .psMuted
                )
            }
            Text(discountText(coupon))
                .font(.psBody)
            Text("Expires \(adminShortDate(coupon.expiry)) · max \(coupon.max_redemptions.map(String.init) ?? "-") redemptions · min KES \(coupon.min_amount ?? 0)")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            HStack(spacing: 10) {
                Button("Edit") { editing = coupon }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .font(.psCaption)
                Button("Redemptions") { redemptionsFor = coupon }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .font(.psCaption)
                Button("Blast") { blastFor = coupon }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .font(.psCaption)
                    .accessibilityLabel("Email coupon \(coupon.code ?? "") to customers")
                Button("Delete", role: .destructive) { confirmDelete = coupon }
                    .buttonStyle(.bordered)
                    .font(.psCaption)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func discountText(_ coupon: AdminCouponRow) -> String {
        if (coupon.discount_type ?? "percent") == "flat" {
            return "KES \(coupon.discountValue) off"
        }
        return "\(coupon.discountValue)% off"
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminCouponsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/coupons")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The coupons endpoint did not return data."
                return
            }
            coupons = result.coupons ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCoupon(_ coupon: AdminCouponRow) async {
        // DELETE /api/v1/admin/coupons/<id>.
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/coupons/\(coupon.id)")
            message = "Coupon \(coupon.code ?? "") deleted."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminCouponFormSheet: View {
    let coupon: AdminCouponRow?
    var onDone: () -> Void

    @State private var code: String
    @State private var discountType = "percent"
    @State private var discountValue: String
    @State private var maxDiscount: String
    @State private var minAmount: String
    @State private var maxRedemptions: String
    @State private var customerType: String
    @State private var serviceRestriction: String
    @State private var expiresAt: String
    @State private var isActive: Bool
    @State private var isWorking = false
    @State private var message: String?

    init(coupon: AdminCouponRow?, onDone: @escaping () -> Void) {
        self.coupon = coupon
        self.onDone = onDone
        _code = State(initialValue: coupon?.code ?? "")
        _discountType = State(initialValue: coupon?.discount_type ?? "percent")
        _discountValue = State(initialValue: coupon.map { "\($0.discountValue)" } ?? "")
        _maxDiscount = State(initialValue: coupon?.max_discount_amount.map(String.init) ?? "")
        _minAmount = State(initialValue: coupon?.min_amount.map(String.init) ?? "")
        _maxRedemptions = State(initialValue: coupon?.max_redemptions.map(String.init) ?? "")
        _customerType = State(initialValue: coupon?.customer_type ?? "")
        _serviceRestriction = State(initialValue: coupon?.service_restriction ?? "")
        _expiresAt = State(initialValue: coupon?.expiry.map { String($0.prefix(10)) } ?? "")
        _isActive = State(initialValue: coupon?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: coupon == nil ? "New coupon" : "Edit coupon")
                            TextField("Code", text: $code)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .psTextField()
                            Picker("Discount type", selection: $discountType) {
                                Text("Percent").tag("percent")
                                Text("Flat amount").tag("flat")
                            }
                            .pickerStyle(.segmented)
                            TextField(discountType == "flat" ? "Discount (KES)" : "Discount (%)", text: $discountValue)
                                .keyboardType(.numberPad)
                                .psTextField()
                            TextField("Max discount (KES, optional)", text: $maxDiscount)
                                .keyboardType(.numberPad)
                                .psTextField()
                            TextField("Minimum amount (KES, optional)", text: $minAmount)
                                .keyboardType(.numberPad)
                                .psTextField()
                            TextField("Max redemptions (optional)", text: $maxRedemptions)
                                .keyboardType(.numberPad)
                                .psTextField()
                            TextField("Customer type (optional)", text: $customerType)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Service restriction (optional)", text: $serviceRestriction)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Expiry date (YYYY-MM-DD, optional)", text: $expiresAt)
                                .autocorrectionDisabled()
                                .psTextField()
                            Toggle("Active", isOn: $isActive)
                                .font(.psBody)
                            Button(coupon == nil ? "Create coupon" : "Save coupon") { Task { await save() } }
                                .psPrimary()
                                .disabled(isWorking || code.isEmpty)
                                .accessibilityLabel(coupon == nil ? "Create coupon" : "Save coupon")
                        }
                    }
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                            .frame(maxWidth: .infinity)
                    }
                    if let message {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .psScreenPadding()
            }
            .adminScreenBackground()
            .navigationTitle(coupon == nil ? "New coupon" : "Edit coupon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .psSheetDetents()
    }

    private func save() async {
        var body: [String: Any] = [
            "code": code.uppercased(),
            "discount_type": discountType,
            "is_active": isActive
        ]
        if let value = Int(discountValue) {
            body["discount_value"] = value
            body["value"] = value
        }
        if let value = Int(maxDiscount) { body["max_discount_amount"] = value }
        if let value = Int(minAmount) { body["min_amount"] = value }
        if let value = Int(maxRedemptions) { body["max_redemptions"] = value }
        if !customerType.isEmpty { body["customer_type"] = customerType }
        if !serviceRestriction.isEmpty { body["service_restriction"] = serviceRestriction }
        if !expiresAt.isEmpty { body["expires_at"] = expiresAt }
        isWorking = true
        defer { isWorking = false }
        do {
            if let coupon {
                _ = try await APIClient.shared.putOK("api/v1/admin/coupons/\(coupon.id)", body: body)
                message = "Coupon saved."
            } else {
                struct CreateResponse: Decodable { let ok: Bool; let coupon_id: Int?; let code: String? }
                let result: CreateResponse = try await APIClient.shared.fetchJSON(
                    "api/v1/admin/coupons", method: "POST", body: body)
                message = "Coupon \(result.code ?? code) created."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminCouponRedemptionsSheet: View {
    let coupon: AdminCouponRow
    @Environment(\.dismiss) private var dismiss
    @State private var redemptions: [AdminGenericRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        PSRingSpinner(diameter: 24, lineWidth: 2)
                            .frame(maxWidth: .infinity)
                    }
                } else if let errorMessage {
                    Section {
                        PSErrorState(message: errorMessage) {
                            Task { await load() }
                        }
                    }
                } else if redemptions.isEmpty {
                    Section {
                        PSEmptyState(
                            systemImage: "ticket.fill",
                            title: "No redemptions yet",
                            body: "Nobody has used this coupon yet."
                        )
                    }
                } else {
                    Section {
                        ForEach(redemptions) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.first("email", "user_id") ?? "Redemption #\(row.id)")
                                    .font(.psHeadline)
                                Text("ID \(row.id) · \(adminShortDate(row.text("created_at")))")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adminScreenBackground()
            .navigationTitle("Redemptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
        .psSheetDetents()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminRedemptionsResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/coupons/\(coupon.id)/redemptions")
            redemptions = result.redemptions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminCouponBlastSheet: View {
    let coupon: AdminCouponRow
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var messageText = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "Email coupon \(coupon.code ?? "")")
                            Text("The coupon is emailed to verified customers. Delivery is best-effort; the response reports how many were attempted.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            TextField("Subject (optional)", text: $subject)
                                .psTextField()
                            TextField("Message (optional)", text: $messageText, axis: .vertical)
                                .lineLimit(4...)
                                .psTextField()
                            Button("Send blast") { Task { await blast() } }
                                .psPrimary()
                                .disabled(isWorking)
                                .accessibilityLabel("Send coupon blast")
                        }
                    }
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                            .frame(maxWidth: .infinity)
                    }
                    if let message {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .psScreenPadding()
            }
            .adminScreenBackground()
            .navigationTitle("Coupon blast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .psSheetDetents()
    }

    private func blast() async {
        // POST /api/v1/admin/coupons/blast returns
        // {"code": ..., "emailed": Int}.
        struct BlastResponse: Decodable { let ok: Bool; let code: String?; let emailed: Int? }
        var body: [String: Any] = ["code": coupon.code ?? ""]
        if !subject.isEmpty { body["subject"] = subject }
        if !messageText.isEmpty { body["message"] = messageText }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: BlastResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/coupons/blast", method: "POST", body: body)
            message = "Coupon \(result.code ?? "") emailed to \(result.emailed ?? 0) customers."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Blog (admin)
// GET /api/v1/admin/blog returns {"ok": true, "posts": [BlogPosts rows]}.
// Create body: {"title", "slug"?, "content", "excerpt", "author",
// "is_published"} returns {"post_id", "slug"}. PUT sends the same
// fields. DELETE /api/v1/admin/blog/<id>.

struct AdminPostRow: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String?
    let slug: String?
    let content: String?
    let excerpt: String?
    let author: String?
    let is_published: Bool?
    let published: Bool?
    let created_at: String?

    var isPublished: Bool { is_published ?? published ?? true }
}

struct AdminBlogResponse: Decodable {
    let ok: Bool
    let posts: [AdminPostRow]?
}

struct AdminBlogRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var posts: [AdminPostRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var editing: AdminPostRow?
    @State private var showCreate = false
    @State private var confirmDelete: AdminPostRow?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && posts.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading blog posts")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, posts.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Blog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New blog post")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) {
            AdminBlogFormSheet(post: nil) {
                showCreate = false
                Task { await load() }
            }
        }
        .sheet(item: $editing) { post in
            AdminBlogFormSheet(post: post) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Delete post?", isPresented: .constant(confirmDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let post = confirmDelete {
                    confirmDelete = nil
                    Task { await deletePost(post) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Post \(confirmDelete?.title ?? "") will be deleted. This cannot be undone.")
        }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if posts.isEmpty {
                    PSEmptyState(
                        systemImage: "doc.text.fill",
                        title: "No blog posts yet",
                        body: "Write the first post to appear on the blog."
                    )
                }
                ForEach(posts) { post in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(post.title ?? "Post #\(post.id)")
                                .font(.psHeadline)
                            Spacer()
                            PSStatusPill(
                                text: post.isPublished ? "Published" : "Draft",
                                systemImage: post.isPublished ? "eye.fill" : "eye.slash.fill",
                                tint: post.isPublished ? .psSuccess : .psMuted
                            )
                        }
                        if let excerpt = post.excerpt, !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                                .lineLimit(2)
                        }
                        Text("\(post.author ?? "-") · \(adminShortDate(post.created_at))")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        HStack(spacing: 10) {
                            Button("Edit") { editing = post }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                                .font(.psCaption)
                            Button("Delete", role: .destructive) { confirmDelete = post }
                                .buttonStyle(.bordered)
                                .font(.psCaption)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminBlogResponse = try await APIClient.shared.fetchJSON("api/v1/admin/blog")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The blog endpoint did not return data."
                return
            }
            posts = result.posts ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePost(_ post: AdminPostRow) async {
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/blog/\(post.id)")
            message = "Post deleted."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminBlogFormSheet: View {
    let post: AdminPostRow?
    var onDone: () -> Void

    @State private var title: String
    @State private var slug: String
    @State private var content: String
    @State private var excerpt: String
    @State private var author: String
    @State private var isPublished: Bool
    @State private var isWorking = false
    @State private var message: String?

    init(post: AdminPostRow?, onDone: @escaping () -> Void) {
        self.post = post
        self.onDone = onDone
        _title = State(initialValue: post?.title ?? "")
        _slug = State(initialValue: post?.slug ?? "")
        _content = State(initialValue: post?.content ?? "")
        _excerpt = State(initialValue: post?.excerpt ?? "")
        _author = State(initialValue: post?.author ?? "")
        _isPublished = State(initialValue: post?.isPublished ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: post == nil ? "New post" : "Edit post")
                            TextField("Title", text: $title)
                                .psTextField()
                            TextField("Slug (optional)", text: $slug)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .psTextField()
                            TextField("Excerpt", text: $excerpt, axis: .vertical)
                                .lineLimit(3...)
                                .psTextField()
                            TextField("Content", text: $content, axis: .vertical)
                                .lineLimit(8...)
                                .psTextField()
                            TextField("Author", text: $author)
                                .autocorrectionDisabled()
                                .psTextField()
                            Toggle("Published", isOn: $isPublished)
                                .font(.psBody)
                            Button(post == nil ? "Create post" : "Save post") { Task { await save() } }
                                .psPrimary()
                                .disabled(isWorking || title.isEmpty)
                                .accessibilityLabel(post == nil ? "Create post" : "Save post")
                        }
                    }
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                            .frame(maxWidth: .infinity)
                    }
                    if let message {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .psScreenPadding()
            }
            .adminScreenBackground()
            .navigationTitle(post == nil ? "New post" : "Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .psSheetDetents()
    }

    private func save() async {
        var body: [String: Any] = [
            "title": title,
            "content": content,
            "excerpt": excerpt,
            "author": author,
            "is_published": isPublished
        ]
        if !slug.isEmpty { body["slug"] = slug }
        isWorking = true
        defer { isWorking = false }
        do {
            if let post {
                _ = try await APIClient.shared.putOK("api/v1/admin/blog/\(post.id)", body: body)
                message = "Post saved."
            } else {
                struct CreateResponse: Decodable { let ok: Bool; let post_id: Int?; let slug: String? }
                _ = try await APIClient.shared.fetchJSON(
                    "api/v1/admin/blog", method: "POST", body: body) as CreateResponse
                message = "Post created."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Help articles (admin)
// GET /api/v1/admin/help returns {"ok": true, "articles": [rows]}.
// Create body: {"title", "slug"?, "content", "category",
// "is_published"} returns {"article_id", "slug"}. PUT sends the
// same fields. DELETE /api/v1/admin/help/<id>.

struct AdminArticleRow: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String?
    let slug: String?
    let content: String?
    let category: String?
    let is_published: Bool?
    let created_at: String?

    var isPublished: Bool { is_published ?? true }
}

struct AdminHelpResponse: Decodable {
    let ok: Bool
    let articles: [AdminArticleRow]?
}

struct AdminHelpRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var articles: [AdminArticleRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var editing: AdminArticleRow?
    @State private var showCreate = false
    @State private var confirmDelete: AdminArticleRow?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && articles.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading help articles")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, articles.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Help articles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New help article")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) {
            AdminHelpFormSheet(article: nil) {
                showCreate = false
                Task { await load() }
            }
        }
        .sheet(item: $editing) { article in
            AdminHelpFormSheet(article: article) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Delete article?", isPresented: .constant(confirmDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let article = confirmDelete {
                    confirmDelete = nil
                    Task { await deleteArticle(article) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Article \(confirmDelete?.title ?? "") will be deleted. This cannot be undone.")
        }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if articles.isEmpty {
                    PSEmptyState(
                        systemImage: "questionmark.circle.fill",
                        title: "No help articles yet",
                        body: "Write the first article for the help centre."
                    )
                }
                ForEach(articles) { article in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(article.title ?? "Article #\(article.id)")
                                .font(.psHeadline)
                            Spacer()
                            PSStatusPill(
                                text: article.isPublished ? "Published" : "Draft",
                                systemImage: article.isPublished ? "eye.fill" : "eye.slash.fill",
                                tint: article.isPublished ? .psSuccess : .psMuted
                            )
                        }
                        Text("\(article.category ?? "-") · \(adminShortDate(article.created_at))")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        HStack(spacing: 10) {
                            Button("Edit") { editing = article }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                                .font(.psCaption)
                            Button("Delete", role: .destructive) { confirmDelete = article }
                                .buttonStyle(.bordered)
                                .font(.psCaption)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminHelpResponse = try await APIClient.shared.fetchJSON("api/v1/admin/help")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The help endpoint did not return data."
                return
            }
            articles = result.articles ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteArticle(_ article: AdminArticleRow) async {
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/help/\(article.id)")
            message = "Article deleted."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminHelpFormSheet: View {
    let article: AdminArticleRow?
    var onDone: () -> Void

    @State private var title: String
    @State private var slug: String
    @State private var content: String
    @State private var category: String
    @State private var isPublished: Bool
    @State private var isWorking = false
    @State private var message: String?

    init(article: AdminArticleRow?, onDone: @escaping () -> Void) {
        self.article = article
        self.onDone = onDone
        _title = State(initialValue: article?.title ?? "")
        _slug = State(initialValue: article?.slug ?? "")
        _content = State(initialValue: article?.content ?? "")
        _category = State(initialValue: article?.category ?? "")
        _isPublished = State(initialValue: article?.isPublished ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: article == nil ? "New article" : "Edit article")
                            TextField("Title", text: $title)
                                .psTextField()
                            TextField("Slug (optional)", text: $slug)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .psTextField()
                            TextField("Category", text: $category)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Content", text: $content, axis: .vertical)
                                .lineLimit(8...)
                                .psTextField()
                            Toggle("Published", isOn: $isPublished)
                                .font(.psBody)
                            Button(article == nil ? "Create article" : "Save article") { Task { await save() } }
                                .psPrimary()
                                .disabled(isWorking || title.isEmpty)
                                .accessibilityLabel(article == nil ? "Create article" : "Save article")
                        }
                    }
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                            .frame(maxWidth: .infinity)
                    }
                    if let message {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .psScreenPadding()
            }
            .adminScreenBackground()
            .navigationTitle(article == nil ? "New article" : "Edit article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .psSheetDetents()
    }

    private func save() async {
        var body: [String: Any] = [
            "title": title,
            "content": content,
            "category": category,
            "is_published": isPublished
        ]
        if !slug.isEmpty { body["slug"] = slug }
        isWorking = true
        defer { isWorking = false }
        do {
            if let article {
                _ = try await APIClient.shared.putOK("api/v1/admin/help/\(article.id)", body: body)
                message = "Article saved."
            } else {
                struct CreateResponse: Decodable { let ok: Bool; let article_id: Int?; let slug: String? }
                _ = try await APIClient.shared.fetchJSON(
                    "api/v1/admin/help", method: "POST", body: body) as CreateResponse
                message = "Article created."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
