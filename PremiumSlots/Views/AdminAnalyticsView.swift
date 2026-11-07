import SwiftUI
import UIKit

// MARK: - Admin analytics, v3 Fix #4 (checklist section 2.1)
// Analytics + financial engine + CSV/PDF exports, from the live
// /api/v1/admin/* endpoints. Admin data only ever comes from the
// live API: when the call fails the screen says so and shows
// nothing at all. No emojis, SF Symbols only, Theme.swift tokens
// only, capped type scale, 16pt padding, 12pt spacing.

// MARK: - Shared admin helpers (used by the other Admin* files too)

/// A row from any admin list endpoint whose columns are not typed
/// in the app (security logs, suggestions, redemptions, ledger).
/// The backend returns flat _row_dict rows, so every value is kept
/// as its string form and looked up by column name.
struct AdminGenericRow: Decodable, Identifiable {
    let id: Int
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: AnyCodable].self)
        values = dict.mapValues { $0.value }
        id = Int(dict["id"]?.value ?? "") ?? 0
    }

    func text(_ key: String) -> String? {
        guard let value = values[key], !value.isEmpty else { return nil }
        return value
    }

    /// First non-empty value among the given column names.
    func first(_ keys: String...) -> String? {
        for key in keys {
            if let value = text(key) { return value }
        }
        return nil
    }
}

/// Short date (YYYY-MM-DD) from an ISO timestamp string.
func adminShortDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "-" }
    return String(value.prefix(10))
}

func adminTempFileURL(data: Data, fileName: String) -> URL? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(fileName)
    do {
        try data.write(to: url, options: .atomic)
        return url
    } catch {
        return nil
    }
}

struct AdminShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// One label/value line, used in admin detail sheets.
struct AdminKVRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Spacer()
            Text(value)
                .font(.psBody)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown by every admin root view when the admin session is not
/// live. Admin screens show nothing at all without the session.
struct AdminNotSignedInView: View {
    var body: some View {
        PSEmptyState(
            systemImage: "lock.fill",
            title: "Admin sign-in required",
            body: "Sign in as admin on the Admin tab first. Admin screens show nothing until the admin session is live."
        )
        .psScreenPadding()
    }
}

// MARK: - Analytics payloads
// GET /api/v1/admin/analytics returns:
// {"ok": true, "days": Int, "service": String, "status": String,
//  "daily_revenue": [{"day": "YYYY-MM-DD", "revenue": Int, "orders": Int}],
//  "totals": {"revenue": Int, "orders": Int},
//  "churn_users": [...], "churn_count": Int, "churn_note": String?}

struct AdminDailyRevenue: Decodable {
    let day: String?
    let revenue: Int?
    let orders: Int?
}

struct AdminAnalyticsTotals: Decodable {
    let revenue: Int?
    let orders: Int?
}

struct AdminAnalyticsResponse: Decodable {
    let ok: Bool
    let days: Int?
    let service: String?
    let status: String?
    let daily_revenue: [AdminDailyRevenue]?
    let totals: AdminAnalyticsTotals?
    let churn_users: [AdminGenericRow]?
    let churn_count: Int?
    let churn_note: String?
}

struct AdminAnalyticsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var days = 30
    @State private var serviceFilter = ""
    @State private var statusFilter = "All"
    @State private var response: AdminAnalyticsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var exportKind = "subscriptions"
    @State private var shareURL: URL?
    @State private var exportError: String?

    private let statusOptions = ["All", "Pending", "Approved", "Initiated", "Cancelled", "Rejected"]
    private let dayOptions = [7, 30, 90]

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && response == nil {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading analytics")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $shareURL) { url in
            AdminShareSheet(urls: [url])
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filters
                totalsSection
                revenueSection
                churnSection
                exportSection
                if let exportError {
                    Text(exportError)
                        .font(.psCaption)
                        .foregroundStyle(.psDanger)
                }
            }
            .psScreenPadding()
        }
    }

    private var filters: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Filters")
                Picker("Days", selection: $days) {
                    ForEach(dayOptions, id: \.self) { value in
                        Text("\(value) days").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { Task { await load() } }
                Picker("Status", selection: $statusFilter) {
                    ForEach(statusOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: statusFilter) { Task { await load() } }
                HStack(spacing: 8) {
                    TextField("Service name (optional)", text: $serviceFilter)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .psTextField()
                    Button("Apply") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                }
            }
        }
    }

    private var totalsSection: some View {
        HStack(spacing: 12) {
            PSCard {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Revenue")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    Text("KES \(response?.totals?.revenue ?? 0)")
                        .font(.psHeadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PSCard {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Orders")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    Text("\(response?.totals?.orders ?? 0)")
                        .font(.psHeadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var revenueSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Daily revenue")
                let rows = response?.daily_revenue ?? []
                if rows.isEmpty {
                    PSEmptyState(
                        systemImage: "chart.bar.fill",
                        title: "No revenue in this range",
                        body: "No ledger entries match the selected days, service and status."
                    )
                } else {
                    let maxRevenue = max(1, rows.map { $0.revenue ?? 0 }.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(rows, id: \.day) { row in
                            VStack(spacing: 4) {
                                Text("KES \(row.revenue ?? 0)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.psPrimary)
                                    .frame(height: max(4, CGFloat(row.revenue ?? 0) / CGFloat(maxRevenue) * 110))
                                Text(String(adminShortDate(row.day).dropFirst(5)))
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Revenue on \(adminShortDate(row.day)): KES \(row.revenue ?? 0), \(row.orders ?? 0) orders")
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    private var churnSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Churn risk")
                let users = response?.churn_users ?? []
                if users.isEmpty {
                    PSEmptyState(
                        systemImage: "person.crop.circle.badge.xmark",
                        title: "No churn list yet",
                        body: response?.churn_note ?? "Churn is a stub on the web: the live endpoint returns an empty list until the backend computes the real list. Nothing is shown here rather than invented churn data."
                    )
                } else {
                    Text("\(response?.churn_count ?? users.count) customers at risk")
                        .font(.psBody)
                    ForEach(users) { user in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.first("name", "email") ?? "Customer")
                                .font(.psHeadline)
                            if let email = user.text("email") {
                                Text(email)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var exportSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Export and report")
                Picker("Export kind", selection: $exportKind) {
                    Text("Subscriptions").tag("subscriptions")
                    Text("Customers").tag("customers")
                    Text("Ledger").tag("ledger")
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    Button("Share CSV") { Task { await shareCSV() } }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("Share \(exportKind) CSV")
                    Button("Share report PDF") { Task { await sharePDF() } }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("Share admin report PDF")
                }
                NavigationLink {
                    AdminFinancialEngineView()
                } label: {
                    PSNavigationRow {
                        Label("Financial engine", systemImage: "banknote.fill")
                            .font(.psBody)
                    }
                }
            }
        }
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var query = "api/v1/admin/analytics?days=\(days)"
        if statusFilter != "All" {
            query += "&status=\(statusFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? statusFilter)"
        }
        let trimmedService = serviceFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedService.isEmpty {
            query += "&service=\(trimmedService.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedService)"
        }
        do {
            let result: AdminAnalyticsResponse = try await APIClient.shared.fetchJSON(query)
            guard result.ok else {
                errorMessage = "Admin needs the live API. The analytics endpoint did not return data."
                return
            }
            response = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareCSV() async {
        exportError = nil
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/export/csv?kind=\(exportKind)")
            if let url = adminTempFileURL(data: data, fileName: "premiumslots-\(exportKind).csv") {
                shareURL = url
            } else {
                exportError = "The CSV could not be saved for sharing."
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func sharePDF() async {
        exportError = nil
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/report/pdf")
            if let url = adminTempFileURL(data: data, fileName: "premiumslots-admin-report.pdf") {
                shareURL = url
            } else {
                exportError = "The report could not be saved for sharing."
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Financial engine
// GET /api/v1/admin/financial-engine returns:
// {"ok": true, "total_revenue": Int, "ledger_entries": Int,
//  "revenue_this_month": Int,
//  "by_service": [{"service_requested": String, "revenue": Int, "orders": Int}],
//  "total_wallet_balances": Int,
//  "wallet_by_action": [{"action_type": String, "total": Int, "n": Int}]}

struct AdminByServiceRow: Decodable {
    let service_requested: String?
    let revenue: Int?
    let orders: Int?
}

struct AdminWalletActionRow: Decodable {
    let action_type: String?
    let total: Int?
    let n: Int?
}

struct AdminFinancialEngineResponse: Decodable {
    let ok: Bool
    let total_revenue: Int?
    let ledger_entries: Int?
    let revenue_this_month: Int?
    let by_service: [AdminByServiceRow]?
    let total_wallet_balances: Int?
    let wallet_by_action: [AdminWalletActionRow]?
}

struct AdminFinancialEngineView: View {
    @EnvironmentObject private var appState: AppState
    @State private var response: AdminFinancialEngineResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && response == nil {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading financial engine")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
        .navigationTitle("Financial engine")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let response {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        engineCard(label: "Total revenue", value: "KES \(response.total_revenue ?? 0)")
                        engineCard(label: "Revenue this month", value: "KES \(response.revenue_this_month ?? 0)")
                        engineCard(label: "Ledger entries", value: "\(response.ledger_entries ?? 0)")
                        engineCard(label: "Wallet balances", value: "KES \(response.total_wallet_balances ?? 0)")
                    }
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "Revenue by service")
                            let rows = response.by_service ?? []
                            if rows.isEmpty {
                                Text("No ledger entries yet.")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                            }
                            ForEach(rows, id: \.service_requested) { row in
                                AdminKVRow(
                                    label: "\(row.service_requested ?? "Service") (\(row.orders ?? 0) orders)",
                                    value: "KES \(row.revenue ?? 0)"
                                )
                            }
                        }
                    }
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "Wallet by action")
                            let rows = response.wallet_by_action ?? []
                            if rows.isEmpty {
                                Text("No wallet transactions yet.")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                            }
                            ForEach(rows, id: \.action_type) { row in
                                AdminKVRow(
                                    label: "\(row.action_type ?? "Action") (\(row.n ?? 0))",
                                    value: "KES \(row.total ?? 0)"
                                )
                            }
                        }
                    }
                }
            }
            .psScreenPadding()
        }
    }

    private func engineCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(value)
                .font(.psHeadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminFinancialEngineResponse = try await APIClient.shared.fetchJSON("api/v1/admin/financial-engine")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The financial engine endpoint did not return data."
                return
            }
            response = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// URL is Identifiable for the share sheet binding.
extension URL: Identifiable {
    var id: String { absoluteString }
}
