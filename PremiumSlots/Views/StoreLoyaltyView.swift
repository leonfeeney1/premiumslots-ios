import SwiftUI

// MARK: - Store, loyalty, achievements, leaderboard, birthday, Fix #4
// Checklist 1.6 and 6.2. Web sources: GET /store (store.py:11),
// app/loyalty.py tiers Bronze 0 / Silver 250 / Gold 750 / Platinum
// 2000, GET /achievements (achievements.py:10), GET /leaderboard
// (referrals.py:10, monthly plus all-time), GET/POST /auth/birthday
// (auth.py:385, date_of_birth YYYY-MM-DD, last credit year, 200-point
// bonus within 3 days before the birthday, once per year).
// All response structs decode with every field optional except ok,
// so a missing field degrades instead of crashing.

// MARK: - Tier thresholds (loyalty.py, mirrored from the server)

func psTierThreshold(_ tier: String) -> Int {
    switch tier.lowercased() {
    case "silver": return 250
    case "gold": return 750
    case "platinum": return 2000
    default: return 0
    }
}

func psTierDiscount(_ tier: String) -> Int {
    switch tier.lowercased() {
    case "silver": return 5
    case "gold": return 10
    case "platinum": return 15
    default: return 0
    }
}

// MARK: - Store response models
// Keys verified against backend/api_v1.py loyalty_store() and
// redeem_reward().

struct PSStoreItem: Decodable {
    let id: Int?
    let name: String?
    let description: String?
    let reward_type: String?
    let points_cost: Int?
    let stock: Int?
    let is_active: Bool?
}

struct PSStoreRedemption: Decodable {
    let id: Int?
    let reward_id: Int?
    let status: String?
    let points_cost: Int?
    let coupon_code: String?
    let created_at: String?
}

struct PSStoreData: Decodable {
    let ok: Bool
    let items: [PSStoreItem]?
    let points: Int?
    let loyalty_tier: String?
    let tier_discount_percent: Int?
    let redemptions: [PSStoreRedemption]?
    let total_spent: Int?
    let total_claims: Int?
}

struct PSStoreRedeemResult: Decodable {
    let ok: Bool
    let error: String?
    let redemption_id: Int?
    let status: String?
    let coupon_code: String?
    let points: Int?
}

// MARK: - Loyalty response models
// Keys verified against backend/api_v1.py my_loyalty().

struct PSLoyaltyNextTier: Decodable {
    let tier: String?
    let points_needed: Int?
    let discount_percent: Int?
}

struct PSLoyaltyLedgerEntry: Decodable {
    let id: Int?
    let points: Int?
    let points_change: Int?
    let reason: String?
    let description: String?
    let action_type: String?
    let created_at: String?
}

struct PSLoyaltyData: Decodable {
    let ok: Bool
    let points: Int?
    let loyalty_tier: String?
    let tier_discount_percent: Int?
    let next_tier: PSLoyaltyNextTier?
    let streak_months: Int?
    let referral_count: Int?
    let ledger: [PSLoyaltyLedgerEntry]?
}

// MARK: - Achievements response models
// Keys verified against backend/api_v1.py my_achievements().
// Each badge definition carries an "earned" flag added by the server.

struct PSBadgeDefinition: Decodable {
    let id: Int?
    let code: String?
    let name: String?
    let description: String?
    let icon: String?
    let category: String?
    let tier: String?
    let earned: Bool?
}

struct PSAchievementStats: Decodable {
    let points: Int?
    let streak_months: Int?
    let referral_count: Int?
}

struct PSAchievementsData: Decodable {
    let ok: Bool
    let badges: [PSBadgeDefinition]?
    let stats: PSAchievementStats?
}

// MARK: - Leaderboard response models
// Keys verified against backend/api_v1.py leaderboard().
// Rows are {name, referrals}; the endpoint is public.

struct PSLeaderboardEntry: Decodable {
    let name: String?
    let referrals: Int?
}

struct PSLeaderboardData: Decodable {
    let ok: Bool
    let monthly: [PSLeaderboardEntry]?
    let all_time: [PSLeaderboardEntry]?
}

// MARK: - Birthday response model
// Keys verified against backend/api_v1.py get_birthday() and
// post_birthday().

struct PSBirthdayData: Decodable {
    let ok: Bool
    let error: String?
    let date_of_birth: String?
    let last_credit_year: Int?
}

// MARK: - Store root

struct StoreRootView: View {
    @State private var data: PSStoreData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var redeemTarget: PSStoreItem?
    @State private var showRedeemConfirm = false
    @State private var redeemBusyId: Int?
    @State private var redeemMessage: String?
    @State private var redeemedCoupon: String?

    private var items: [PSStoreItem] {
        (data?.items ?? []).sorted { ($0.points_cost ?? 0) < ($1.points_cost ?? 0) }
    }

    private var redemptions: [PSStoreRedemption] {
        data?.redemptions ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading rewards store")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    storeList
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Rewards store")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Redeem this reward?", isPresented: $showRedeemConfirm) {
                Button("Cancel", role: .cancel) { redeemTarget = nil }
                Button("Redeem") {
                    if let target = redeemTarget {
                        Task { await redeem(target) }
                    }
                }
            } message: {
                if let target = redeemTarget {
                    Text("Spend \(target.points_cost ?? 0) points on \(target.name ?? "this reward")? Redemptions start as Pending.")
                }
            }
            .task { await load() }
        }
    }

    private var storeList: some View {
        List {
            Section {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("My points", systemImage: "star.fill")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Text("\(data?.points ?? 0) points")
                            .font(.psTitle)
                        HStack(spacing: 8) {
                            if let tier = data?.loyalty_tier {
                                PSStatusPill(text: tier, systemImage: "rosette", tint: .psPrimary)
                            }
                            if let discount = data?.tier_discount_percent, discount > 0 {
                                Text("\(discount)% tier saving")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        HStack(spacing: 16) {
                            Text("\(data?.total_claims ?? 0) claims")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text("\(data?.total_spent ?? 0) points spent")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if let message = redeemMessage {
                            Text(message)
                                .font(.psBody)
                                .foregroundStyle(.psSuccess)
                        }
                        if let coupon = redeemedCoupon {
                            HStack {
                                Text("Your code: \(coupon)")
                                    .font(.psMono)
                                Button {
                                    UIPasteboard.general.string = coupon
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 20))
                                }
                                .accessibilityLabel("Copy reward code \(coupon)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Rewards") {
                if items.isEmpty {
                    PSEmptyState(
                        systemImage: "gift",
                        title: "No rewards right now",
                        body: "Rewards you can claim with loyalty points will show here, cheapest first."
                    )
                } else {
                    ForEach(items, id: \.id) { item in
                        PSStoreItemRow(
                            item: item,
                            myPoints: data?.points ?? 0,
                            isBusy: redeemBusyId == item.id
                        ) {
                            redeemTarget = item
                            showRedeemConfirm = true
                        }
                    }
                }
            }

            Section("My redemptions") {
                if redemptions.isEmpty {
                    PSEmptyState(
                        systemImage: "ticket",
                        title: "No redemptions yet",
                        body: "Rewards you claim will show here with their status and code."
                    )
                } else {
                    ForEach(redemptions, id: \.id) { redemption in
                        PSStoreRedemptionRow(redemption: redemption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .refreshable { await load() }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSStoreData = try await APIClient.shared.fetchJSON("api/v1/store")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }

    private func redeem(_ item: PSStoreItem) async {
        guard let id = item.id else { return }
        redeemBusyId = id
        defer { redeemBusyId = nil }
        redeemMessage = nil
        redeemedCoupon = nil
        do {
            let result: PSStoreRedeemResult = try await APIClient.shared.fetchJSON(
                "api/v1/store/redeem/\(id)", method: "POST")
            redeemMessage = "Redeemed \(item.name ?? "reward"). Status: \(result.status ?? "Pending"). Points left: \(result.points ?? (data?.points ?? 0))."
            if let coupon = result.coupon_code {
                redeemedCoupon = coupon
            }
            redeemTarget = nil
            await load()
        } catch {
            redeemTarget = nil
            // Surface the failure inline instead of replacing the list.
            redeemMessage = error.localizedDescription
        }
    }
}

struct PSStoreItemRow: View {
    let item: PSStoreItem
    let myPoints: Int
    let isBusy: Bool
    let onRedeem: () -> Void

    private var outOfStock: Bool {
        if let stock = item.stock { return stock <= 0 }
        return false
    }

    private var affordable: Bool {
        myPoints >= (item.points_cost ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name ?? "Reward")
                    .font(.psHeadline)
                Spacer()
                Text("\(item.points_cost ?? 0) pts")
                    .font(.psMono)
                    .foregroundStyle(.psPrimary)
            }
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.psBody)
                    .foregroundStyle(.psDim)
            }
            HStack(spacing: 8) {
                if let type = item.reward_type, !type.isEmpty {
                    Text(psCapitalized(type.replacingOccurrences(of: "_", with: " ")))
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if let stock = item.stock {
                    Text(stock > 0 ? "\(stock) left" : "Out of stock")
                        .font(.psCaption)
                        .foregroundStyle(stock > 0 ? .psMuted : .psDanger)
                }
            }
            HStack {
                Spacer()
                if isBusy {
                    PSRingSpinner(diameter: 20, lineWidth: 2)
                } else {
                    Button(outOfStock ? "Out of stock" : (affordable ? "Redeem" : "Not enough points")) {
                        onRedeem()
                    }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .disabled(outOfStock || !affordable)
                    .accessibilityLabel("Redeem \(item.name ?? "reward") for \(item.points_cost ?? 0) points")
                }
            }
        }
        .psTouchTarget()
    }
}

struct PSStoreRedemptionRow: View {
    let redemption: PSStoreRedemption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(redemption.points_cost ?? 0) points")
                    .font(.psBody)
                Spacer()
                if let status = redemption.status, !status.isEmpty {
                    PSStatusPill(
                        text: psCapitalized(status),
                        systemImage: status.lowercased() == "pending" ? "clock.fill" : "checkmark.circle.fill",
                        tint: status.lowercased() == "pending" ? .psWarning : .psSuccess
                    )
                }
            }
            if let coupon = redemption.coupon_code, !coupon.isEmpty {
                HStack {
                    Text(coupon)
                        .font(.psMono)
                    Button {
                        UIPasteboard.general.string = coupon
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 20))
                    }
                    .accessibilityLabel("Copy reward code \(coupon)")
                }
            }
            Text("Claimed \(psShortDate(redemption.created_at))")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
        .psTouchTarget()
    }
}

// MARK: - Loyalty root

struct LoyaltyRootView: View {
    @State private var data: PSLoyaltyData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var points: Int { data?.points ?? 0 }
    private var tier: String { data?.loyalty_tier ?? "Bronze" }

    private var progress: Double {
        guard let next = data?.next_tier, let needed = next.points_needed else { return 1 }
        let currentThreshold = psTierThreshold(tier)
        let nextThreshold = currentThreshold + needed
        guard nextThreshold > currentThreshold else { return 1 }
        return min(1, max(0, Double(points - currentThreshold) / Double(nextThreshold - currentThreshold)))
    }

    private var ledger: [PSLoyaltyLedgerEntry] {
        data?.ledger ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading loyalty")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    loyaltyList
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Loyalty")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var loyaltyList: some View {
        List {
            Section {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(points) points")
                                .font(.psTitle)
                            Spacer()
                            PSStatusPill(text: tier, systemImage: "rosette", tint: .psPrimary)
                        }
                        Text("1 point per KES spent, 2 points per day of membership, 100 points per completed referral, 50 points per review.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        if let next = data?.next_tier, let needed = next.points_needed, let nextName = next.tier {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(needed) points to \(nextName)")
                                    .font(.psBody)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.psBorder)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.psCyan)
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 8)
                                .accessibilityLabel("\(needed) points to \(nextName) tier")
                                if let discount = next.discount_percent {
                                    Text("\(nextName) saves \(discount)%")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                        } else {
                            Text("Top tier reached. Platinum saves 15%.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                        }
                        HStack(spacing: 16) {
                            Text("Streak \(data?.streak_months ?? 0) months")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text("\(data?.referral_count ?? 0) referrals")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Streak milestones") {
                Text("Consecutive months of active cover earn bonus points: 1 month 50, 3 months 120, 6 months 300, 12 months 800.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                HStack {
                    Text("Current streak")
                    Spacer()
                    Text("\(data?.streak_months ?? 0) months")
                        .font(.psMono)
                }
            }

            Section("Points history") {
                if ledger.isEmpty {
                    PSEmptyState(
                        systemImage: "list.bullet",
                        title: "No points history yet",
                        body: "Points you earn from spending, referrals, reviews and streaks will show here."
                    )
                } else {
                    ForEach(ledger, id: \.id) { entry in
                        PSLoyaltyLedgerRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .refreshable { await load() }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSLoyaltyData = try await APIClient.shared.fetchJSON("api/v1/me/loyalty")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }
}

struct PSLoyaltyLedgerRow: View {
    let entry: PSLoyaltyLedgerEntry

    private var label: String {
        if let reason = entry.reason, !reason.isEmpty { return reason }
        if let description = entry.description, !description.isEmpty { return description }
        if let action = entry.action_type, !action.isEmpty { return action }
        return "Points update"
    }

    private var change: Int? {
        entry.points_change ?? entry.points
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 20))
                .foregroundStyle(.psAmber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.psBody)
                Text(psShortDate(entry.created_at))
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            if let change {
                Text("\(change >= 0 ? "+" : "")\(change) pts")
                    .font(.psMono)
                    .foregroundStyle(change >= 0 ? .psSuccess : .psText)
            }
        }
        .psTouchTarget()
    }
}

// MARK: - Achievements root

struct AchievementsRootView: View {
    @State private var data: PSAchievementsData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var badges: [PSBadgeDefinition] {
        data?.badges ?? []
    }

    private var earnedCount: Int {
        badges.filter { $0.earned == true }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading achievements")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    achievementsScroll
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var achievementsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(earnedCount) of \(badges.count) badges earned")
                            .font(.psHeadline)
                        HStack(spacing: 16) {
                            Text("\(data?.stats?.points ?? 0) points")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text("Streak \(data?.stats?.streak_months ?? 0) months")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text("\(data?.stats?.referral_count ?? 0) referrals")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if badges.isEmpty {
                    PSEmptyState(
                        systemImage: "rosette",
                        title: "No badges yet",
                        body: "Badges are earned for first and milestone subscriptions, streaks, referrals, coupons and birthday bonuses."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(badges, id: \.id) { badge in
                            PSAchievementCell(badge: badge)
                        }
                    }
                }
            }
            .psScreenPadding()
        }
        .refreshable { await load() }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSAchievementsData = try await APIClient.shared.fetchJSON("api/v1/me/achievements")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }
}

struct PSAchievementCell: View {
    let badge: PSBadgeDefinition

    private var earned: Bool { badge.earned == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: earned ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(earned ? .psSuccess : .psMuted)
                    .accessibilityHidden(true)
                Spacer()
                if let category = badge.category, !category.isEmpty {
                    Text(category)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Text(badge.name ?? "Badge")
                .font(.psHeadline)
            if let description = badge.description, !description.isEmpty {
                Text(description)
                    .font(.psBody)
                    .foregroundStyle(.psDim)
            }
            if let tier = badge.tier, !tier.isEmpty {
                Text(tier)
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Text(earned ? "Earned" : "Locked")
                .font(.psCaption)
                .foregroundStyle(earned ? .psSuccess : .psMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.psBorder, lineWidth: 1))
        .opacity(earned ? 1 : 0.65)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.name ?? "Badge"), \(earned ? "earned" : "locked")")
    }
}

// MARK: - Leaderboard root (public endpoint)

struct LeaderboardRootView: View {
    @State private var data: PSLeaderboardData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var period = "monthly"

    private var entries: [PSLeaderboardEntry] {
        period == "monthly" ? (data?.monthly ?? []) : (data?.all_time ?? [])
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading leaderboard")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    leaderboardList
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var leaderboardList: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    Text("This month").tag("monthly")
                    Text("All time").tag("all_time")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Leaderboard period")
                Text("Top referrers by completed referrals.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }

            Section(period == "monthly" ? "This month" : "All time") {
                if entries.isEmpty {
                    PSEmptyState(
                        systemImage: "trophy",
                        title: "No referrers yet",
                        body: "Completed referrals will rank here. Invite a friend to take the top spot."
                    )
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        PSLeaderboardRow(rank: index + 1, entry: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .refreshable { await load() }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSLeaderboardData = try await APIClient.shared.fetchJSON("api/v1/leaderboard")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }
}

struct PSLeaderboardRow: View {
    let rank: Int
    let entry: PSLeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.psHeadline)
                .foregroundStyle(rank <= 3 ? .psAmber : .psMuted)
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            Image(systemName: rank == 1 ? "trophy.fill" : "person.fill")
                .font(.system(size: 20))
                .foregroundStyle(rank == 1 ? .psAmber : .psMuted)
                .accessibilityHidden(true)
            Text(entry.name ?? "Member")
                .font(.psBody)
            Spacer()
            Text("\(entry.referrals ?? 0) referrals")
                .font(.psMono)
                .foregroundStyle(.psMuted)
        }
        .psTouchTarget()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.name ?? "Member"), \(entry.referrals ?? 0) referrals")
    }
}

// MARK: - Birthday save screen

struct BirthdaySaveView: View {
    @State private var selectedDate = Date()
    @State private var hasSavedDate = false
    @State private var lastCreditYear: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var isSaving = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading birthday")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, !hasSavedDate {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    birthdayForm
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private var birthdayForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save your date of birth to get a 200-point birthday bonus. The bonus is credited within 3 days before your birthday, once per year.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)

                PSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker(
                            "Date of birth",
                            selection: $selectedDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .font(.psBody)
                        .accessibilityLabel("Date of birth")
                        if hasSavedDate {
                            Text("Saved as \(Self.dayFormatter.string(from: selectedDate))")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if let year = lastCreditYear {
                            Text("Birthday bonus last credited in \(year).")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.psBody)
                        .foregroundStyle(.psDanger)
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(.psBody)
                        .foregroundStyle(.psSuccess)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper)
                    } else {
                        Text("Save birthday")
                    }
                }
                .psPrimary()
                .disabled(isSaving)
                .accessibilityLabel("Save birthday")
            }
            .psScreenPadding()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh: PSBirthdayData = try await APIClient.shared.fetchJSON("api/v1/me/birthday")
            lastCreditYear = fresh.last_credit_year
            if let text = fresh.date_of_birth,
               let date = Self.dayFormatter.date(from: String(text.prefix(10))) {
                selectedDate = date
                hasSavedDate = true
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        errorMessage = nil
        saveMessage = nil
        isSaving = true
        defer { isSaving = false }
        let text = Self.dayFormatter.string(from: selectedDate)
        do {
            let result: PSBirthdayData = try await APIClient.shared.fetchJSON(
                "api/v1/me/birthday", method: "POST", body: ["date_of_birth": text])
            if let saved = result.date_of_birth {
                saveMessage = "Birthday saved as \(saved)."
            } else {
                saveMessage = "Birthday saved as \(text)."
            }
            hasSavedDate = true
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
