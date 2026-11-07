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

/// Parse an expiry value the API sends: a YYYY-MM-DD date or a
/// full ISO timestamp. Returns nil when there is no usable date.
func adminExpiryDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }
    let plain = DateFormatter()
    plain.locale = Locale(identifier: "en_US_POSIX")
    plain.dateFormat = "yyyy-MM-dd"
    return plain.date(from: String(value.prefix(10)))
}

/// Days from today (start of day) to the expiry date. Prefers the
/// server value when present, otherwise computes it locally from
/// expiry_date. Negative means already expired.
func adminDaysRemaining(expiryDate: String?, apiDays: Int?) -> Int? {
    if let apiDays { return apiDays }
    guard let expiry = adminExpiryDate(expiryDate) else { return nil }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let end = calendar.startOfDay(for: expiry)
    return calendar.dateComponents([.day], from: today, to: end).day
}

/// Plain-language days-left label. Never shows a negative number:
/// a past expiry reads as Expired.
func adminDaysLeftText(expiryDate: String?, apiDays: Int?) -> String {
    guard let days = adminDaysRemaining(expiryDate: expiryDate, apiDays: apiDays) else {
        return "No expiry date"
    }
    if days < 0 { return "Expired" }
    if days == 0 { return "Expires today" }
    if days == 1 { return "1d left" }
    return "\(days)d left"
}

/// Tint for a days-left label: red once expired, amber today,
/// muted while time remains.
func adminDaysLeftTint(expiryDate: String?, apiDays: Int?) -> Color {
    guard let days = adminDaysRemaining(expiryDate: expiryDate, apiDays: apiDays) else {
        return .psMuted
    }
    if days < 0 { return .psDanger }
    if days == 0 { return .psAmber }
    return .psMuted
}

/// One flexible number: the API sometimes sends an Int, sometimes
/// a Double (a SQL SUM) or a numeric string. Decodes all three so
/// one shape change does not blank a whole screen.
struct AdminFlexInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue)
        } else if let text = try? container.decode(String.self) {
            value = Int(text)
        } else {
            value = nil
        }
    }
}

extension KeyedDecodingContainer {
    /// Read an Int field that may arrive as Int, Double or String.
    func adminInt(forKey key: Key) -> Int? {
        (try? decodeIfPresent(AdminFlexInt.self, forKey: key))??.value
    }
    /// Read a Double field that may arrive as Double, Int or String.
    func adminDouble(forKey key: Key) -> Double? {
        if let intValue = adminInt(forKey: key) { return Double(intValue) }
        return nil
    }
}

/// One full-width admin action row: icon, label and a distinct
/// tint, with a 44pt minimum touch target. Used by the subscription
/// and customer detail sheets so actions are never a row of
/// same-colour cramped buttons.
struct AdminActionButton: View {
    let label: String
    let systemImage: String
    let tint: Color
    var isDestructive = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil) {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.psBody)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.psHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
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
// GET /api/v1/admin/analytics returns the new contract:
// {"ok": true, "revenue_by_day": [{"day", "revenue", "orders"}],
//  "by_service": [{"service", "revenue", "orders"}],
//  "by_status": [{"status", "count"}],
//  "churn": null | {"count": Int, "users": [...], "note": String},
//  "totals": {"revenue": Int, "orders": Int}}
// The live backend in the workspace still returns the older keys
// (daily_revenue, churn_users, churn_count, churn_note, plus
// top_services / status as labels-and-data objects and a totals
// object that the extras overwrite), so every field below decodes
// BOTH shapes and both number forms (Int, Double, String). A
// missing or null metric stays nil and the screen says so honestly
// instead of showing 0 or a blank screen.

struct AdminDailyRevenue: Decodable {
    let day: String?
    let revenue: Int?
    let orders: Int?

    enum CodingKeys: String, CodingKey {
        case day, date, revenue, orders, count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decodeIfPresent(String.self, forKey: .day)
            ?? container.decodeIfPresent(String.self, forKey: .date)
        revenue = container.adminInt(forKey: .revenue)
        orders = container.adminInt(forKey: .orders)
            ?? container.adminInt(forKey: .count)
    }
}

struct AdminAnalyticsTotals: Decodable {
    let revenue: Int?
    let orders: Int?

    enum CodingKeys: String, CodingKey {
        case revenue, orders, users, active_subs, revenue_this_month
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revenue = container.adminInt(forKey: .revenue)
        orders = container.adminInt(forKey: .orders)
    }
}

/// One row of a labels-and-data object, e.g. {"labels": [...],
/// "data": [...]}, which the backend uses for top_services and
/// ticket status. Converted to the same row shape as by_service.
struct AdminLabelledSeries: Decodable {
    let labels: [String]?
    let data: [Double]?
}

struct AdminByStatusRow: Decodable, Identifiable {
    let status: String
    let count: Int
    let revenue: Int?

    var id: String { status }

    init(status: String, count: Int, revenue: Int?) {
        self.status = status
        self.count = count
        self.revenue = revenue
    }

    enum CodingKeys: String, CodingKey {
        case status, label, name, service_requested, count, orders, n, value, revenue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .service_requested)
            ?? "Unknown"
        count = container.adminInt(forKey: .count)
            ?? container.adminInt(forKey: .orders)
            ?? container.adminInt(forKey: .n)
            ?? container.adminInt(forKey: .value)
            ?? 0
        revenue = container.adminInt(forKey: .revenue)
    }
}

/// Churn as the contract defines it: null means not available yet,
/// an object carries a count, a user list and an optional note, an
/// array is a plain user list. The older backend shape
/// (churn_users / churn_count / churn_note) is read as a fallback.
struct AdminChurn: Decodable {
    let available: Bool
    let count: Int?
    let users: [AdminGenericRow]
    let note: String?

    static let unavailable = AdminChurn(available: false, count: nil, users: [], note: nil)

    init(available: Bool, count: Int?, users: [AdminGenericRow], note: String?) {
        self.available = available
        self.count = count
        self.users = users
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case count, total, at_risk, users, list, note
    }

    init(from decoder: Decoder) throws {
        // Try the object shape first: a keyed container on a null
        // or array value throws without consuming the decoder, so
        // the single-value shapes below still decode afterwards.
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
            let count = keyed.adminInt(forKey: .count)
                ?? keyed.adminInt(forKey: .total)
                ?? keyed.adminInt(forKey: .at_risk)
            let users = (try? keyed.decodeIfPresent([AdminGenericRow].self, forKey: .users))
                ?? (try? keyed.decodeIfPresent([AdminGenericRow].self, forKey: .list))
                ?? []
            let note = try keyed.decodeIfPresent(String.self, forKey: .note)
            self.init(available: true, count: count ?? users.count, users: users, note: note)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unavailable
            return
        }
        if let users = try? container.decode([AdminGenericRow].self) {
            self.init(available: true, count: users.count, users: users, note: nil)
            return
        }
        if let count = try? container.decode(Int.self) {
            self.init(available: true, count: count, users: [], note: nil)
            return
        }
        self = .unavailable
    }
}

struct AdminAnalyticsResponse: Decodable {
    let ok: Bool
    let days: Int?
    let service: String?
    let status: String?
    let dailyRevenue: [AdminDailyRevenue]
    let totals: AdminAnalyticsTotals?
    var byService: [AdminByServiceRow]?
    var byStatus: [AdminByStatusRow]?
    let churn: AdminChurn

    /// Legacy accessors kept so existing call sites keep working.
    var daily_revenue: [AdminDailyRevenue]? { dailyRevenue.isEmpty ? nil : dailyRevenue }
    var churn_users: [AdminGenericRow]? { churn.users.isEmpty ? nil : churn.users }
    var churn_count: Int? { churn.count }
    var churn_note: String? { churn.note }

    enum CodingKeys: String, CodingKey {
        case ok, days, service, status
        case revenue_by_day, daily_revenue
        case totals
        case by_service, top_services
        case by_status
        case churn, churn_users, churn_count, churn_note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        days = container.adminInt(forKey: .days)
        // Tolerant on purpose: the backend's extras overwrite the
        // echoed "status" string with a labels-and-data object, so
        // a strict String decode here would throw and blank the
        // whole screen. A mismatched type reads as nil instead.
        service = (try? container.decodeIfPresent(String.self, forKey: .service)) ?? nil
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        let newDays = try container.decodeIfPresent([AdminDailyRevenue].self, forKey: .revenue_by_day)
        let oldDays = try container.decodeIfPresent([AdminDailyRevenue].self, forKey: .daily_revenue)
        dailyRevenue = newDays ?? oldDays ?? []
        totals = try container.decodeIfPresent(AdminAnalyticsTotals.self, forKey: .totals)
        var serviceRows = try container.decodeIfPresent([AdminByServiceRow].self, forKey: .by_service)
        if serviceRows == nil,
           let series = try container.decodeIfPresent(AdminLabelledSeries.self, forKey: .top_services),
           let labels = series.labels, let data = series.data {
            serviceRows = zip(labels, data).map { AdminByServiceRow(service: $0, revenue: Int($1), orders: nil) }
        }
        byService = serviceRows
        var statusRows = try container.decodeIfPresent([AdminByStatusRow].self, forKey: .by_status)
        if statusRows == nil,
           let series = try container.decodeIfPresent(AdminLabelledSeries.self, forKey: .status),
           let labels = series.labels, let data = series.data {
            statusRows = zip(labels, data).map { AdminByStatusRow(status: $0, count: Int($1), revenue: nil) }
        }
        byStatus = statusRows
        if let churnValue = try? container.decodeIfPresent(AdminChurn.self, forKey: .churn),
           let churnValue {
            churn = churnValue
        } else {
            let users = try container.decodeIfPresent([AdminGenericRow].self, forKey: .churn_users) ?? []
            let count = container.adminInt(forKey: .churn_count)
            let note = try container.decodeIfPresent(String.self, forKey: .churn_note)
            let hasLegacyKeys = (try? container.decodeIfPresent([AdminGenericRow].self, forKey: .churn_users)) != nil
                || count != nil || note != nil
            if hasLegacyKeys {
                // The older backend returns an empty list with a note
                // when the real list could not be built: that is an
                // unavailable metric, not zero churn.
                if users.isEmpty, let note, !note.isEmpty {
                    churn = AdminChurn(available: false, count: nil, users: [], note: note)
                } else {
                    churn = AdminChurn(available: true, count: count ?? users.count, users: users, note: note)
                }
            } else {
                churn = .unavailable
            }
        }
    }
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
            } else if let errorMessage, response == nil {
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
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL {
                AdminShareSheet(urls: [url])
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filters
                if let errorMessage, response != nil {
                    Text(errorMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psDanger)
                }
                totalsSection
                revenueSection
                byServiceSection
                byStatusSection
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
        .scrollIndicators(.hidden)
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
                    if let revenue = response?.totals?.revenue {
                        Text("KES \(revenue)")
                            .font(.psHeadline)
                    } else {
                        Text("Not available yet")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PSCard {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Orders")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    if let orders = response?.totals?.orders {
                        Text("\(orders)")
                            .font(.psHeadline)
                    } else {
                        Text("Not available yet")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var revenueSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Daily revenue")
                let allRows = response?.dailyRevenue ?? []
                // A 90-day chart of 90 bars is unreadable, so the
                // chart shows the most recent 14 days and says so.
                let rows = allRows.count > 14 ? Array(allRows.suffix(14)) : allRows
                if allRows.isEmpty {
                    PSEmptyState(
                        systemImage: "chart.bar.fill",
                        title: "No revenue in this range",
                        body: "No ledger entries match the selected days, service and status."
                    )
                } else {
                    if allRows.count > 14 {
                        Text("Showing the most recent 14 days of \(allRows.count).")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
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

    private var byServiceSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Revenue by service")
                if let rows = response?.byService {
                    if rows.isEmpty {
                        Text("No revenue by service in this range.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    ForEach(rows, id: \.service_requested) { row in
                        AdminKVRow(
                            label: "\(row.service_requested ?? "Service") (\(row.orders ?? 0) orders)",
                            value: "KES \(row.revenue ?? 0)"
                        )
                    }
                } else {
                    Text("Not available yet")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
            }
        }
    }

    private var byStatusSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Subscriptions by status")
                if let rows = response?.byStatus {
                    if rows.isEmpty {
                        Text("No subscriptions by status yet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    ForEach(rows) { row in
                        AdminKVRow(
                            label: row.status,
                            value: "\(row.count)"
                        )
                    }
                } else {
                    Text("Not available yet")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
            }
        }
    }

    private var churnSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Churn risk")
                if response == nil {
                    Text("Not available yet")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                } else if let churn = response?.churn, !churn.available {
                    Text(churn.note ?? "Churn is not available yet.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                } else if let churn = response?.churn, churn.users.isEmpty {
                    Text("No customers at risk right now.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                } else if let churn = response?.churn {
                    Text("\(churn.count ?? churn.users.count) customers at risk")
                        .font(.psBody)
                    ForEach(churn.users) { user in
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
            var result: AdminAnalyticsResponse = try await APIClient.shared.fetchJSON(query)
            guard result.ok else {
                errorMessage = "Admin needs the live API. The analytics endpoint did not return data."
                return
            }
            // The older backend keeps revenue by service only in the
            // financial engine, not in analytics: fill it from there
            // so the section shows real numbers instead of
            // "Not available yet" when the data does exist.
            if result.byService == nil,
               let engine: AdminFinancialEngineResponse = try? await APIClient.shared.fetchJSON("api/v1/admin/financial-engine"),
               engine.ok {
                result.byService = engine.by_service
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

    init(service: String, revenue: Int?, orders: Int?) {
        self.service_requested = service
        self.revenue = revenue
        self.orders = orders
    }

    enum CodingKeys: String, CodingKey {
        case service_requested, service, name, revenue, total, monthly_recurring, orders, count, n
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        service_requested = try container.decodeIfPresent(String.self, forKey: .service_requested)
            ?? container.decodeIfPresent(String.self, forKey: .service)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        revenue = container.adminInt(forKey: .revenue)
            ?? container.adminInt(forKey: .total)
            ?? container.adminInt(forKey: .monthly_recurring)
        orders = container.adminInt(forKey: .orders)
            ?? container.adminInt(forKey: .count)
            ?? container.adminInt(forKey: .n)
    }
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
        .scrollIndicators(.hidden)
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
