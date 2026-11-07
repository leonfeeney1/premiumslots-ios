import SwiftUI

// MARK: - Home, v5 (v6: richer hero + resilient refresh)
// First tab. One clean hero lockup: the real extended lockup only
// (shield plus wordmark once, in a single image), with a subtle
// gradient behind it. No second logo beside it and no stray favicon
// anywhere on Home. Live stats as elegant cards from the catalogue
// API (platforms, slots in rotation, slots available now), a
// featured platforms grid with real logos, a going-fast ranking
// from live stock, a 3-step How it works visual, a why section
// with factual service copy only, a short FAQ, and a support
// section with the real WhatsApp support link. Every number comes
// from the live API; while loading, skeleton shapes show, and on
// failure an error state with retry shows only when there is
// nothing to show at all.
//
// Refresh (v6): the pull-to-refresh path is resilient. The
// catalogue call, the subscriptions call and the notification
// bell each guard their own failure, so one failing call cannot
// fail the whole refresh. A catalogue that is not live shows the
// saved catalogue with a small neutral pill, never a
// "something went wrong" state, while saved or bundled platforms
// are on screen. The error state appears only on a first load
// with no platforms at all, and a successful refresh always
// clears the stale error.
//
// Safe area: the screen lives in a NavigationStack with an inline
// title, so content starts below the notch and Dynamic Island on
// first appearance and only scrolls under the bar once the user
// scrolls. The navigation bar background is an opaque brand colour
// so scrolled content never shows through behind the notch. No
// ignoresSafeArea is used on this screen. The background colour
// extends edge to edge under the tab bar through psScreenBackground.

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    var onBrowseCatalogue: () -> Void = {}
    var onOpenMySlots: () -> Void = {}
    var onOpenSupport: () -> Void = {}

    @State private var selectedPlatform: Platform?
    @State private var loadError: String?
    @State private var isLoading = false

    /// True only on the very first load, before any catalogue
    /// (live or saved) has ever been shown.
    private var isFirstLoad: Bool {
        isLoading && appState.liveState == .unknown
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    if let loadError, appState.platforms.isEmpty {
                        PSErrorState(message: loadError) {
                            Task { await load() }
                        }
                    } else {
                        statsSection
                        mySlotsStrip
                        featuredSection
                        goingFastSection
                        howItWorksSection
                        whyChooseUsSection
                        faqSection
                        supportSection
                    }
                }
                .padding(16)
            }
            .psHiddenScrollIndicators()
            .scrollDismissesKeyboard(.interactively)
            .psScreenBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { CustomerNotificationBell() }
            }
            .refreshable { await load() }
            .sheet(item: $selectedPlatform) { platform in
                PlatformDetailView(platform: platform)
                    .psSheetDetents()
            }
            .task { await load() }
            .safeAreaPadding(.bottom, 8)
        }
    }

    // MARK: - Loading, resilient per call

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // A successful-but-empty catalogue must not blank Home when
        // a saved or bundled list is already on screen: keep that
        // list and show the "Saved catalogue" pill instead.
        let previousPlatforms = appState.platforms
        // Catalogue: refreshCatalogue never throws. It keeps the
        // saved catalogue and marks the state offline when the API
        // cannot be reached, so this call alone can never fail the
        // refresh.
        await appState.refreshCatalogue()
        if appState.platforms.isEmpty, !previousPlatforms.isEmpty {
            appState.platforms = previousPlatforms
            appState.liveState = .offline
            appState.refreshMessage = "Saved catalogue"
        }
        // Subscriptions: refreshMySubscriptions guards its own
        // failure internally and keeps the last list, so this call
        // cannot fail the refresh either.
        if appState.isLoggedIn {
            await appState.refreshMySubscriptions()
        }
        // Only a first load with no platforms at all is an error.
        // With saved platforms on screen, the offline pill in the
        // stats section is the whole story, and a stale error is
        // always cleared on a successful refresh.
        if appState.liveState == .live {
            loadError = nil
        } else if appState.platforms.isEmpty {
            loadError = "The latest catalogue could not be loaded. Check your connection and try again."
        } else {
            loadError = nil
        }
    }

    private var slotsAvailableNow: Int {
        appState.platforms.reduce(0) { $0 + $1.slotsLeft }
    }

    private var featuredPlatforms: [Platform] {
        let available = appState.platforms.filter { !$0.isSoldOut }
        return Array((available.isEmpty ? appState.platforms : available).prefix(6))
    }

    /// Lowest stock first: the platforms closest to selling out,
    /// from live stock only. Scarcity is the honest ranking the
    /// app can compute without inventing demand.
    private var goingFastPlatforms: [Platform] {
        let available = appState.platforms.filter { !$0.isSoldOut }
        return Array(available.sorted { $0.slotsLeft < $1.slotsLeft }.prefix(3))
    }

    private var activeSlotCount: Int {
        appState.liveSubscriptions.filter { $0.status == "Approved" }.count
    }

    private func toggleWaitlist(for platform: Platform) {
        if appState.waitlist.contains(platform.id) {
            appState.leaveWaitlist(platformId: platform.id)
        } else {
            appState.joinWaitlist(platformId: platform.id)
        }
    }

    // MARK: - Hero: one lockup, once, richer

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                LogoLockupView(height: 44)
                Spacer()
                if appState.liveState == .live {
                    PSStatusPill(text: "Live catalogue", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                } else if appState.liveState == .offline {
                    PSStatusPill(text: "Saved catalogue", systemImage: "wifi.slash", tint: .psMuted)
                }
            }
            Text("Shared subscriptions, one slot at a time.")
                .psTextStyle(.largeTitle)
            Text("Premium streaming, music, design and learning accounts, shared fairly. Pay by M-PESA and get your own profile.")
                .psTextStyle(.body)
                .foregroundStyle(.psMuted)
            HStack(spacing: 10) {
                Button("Browse the catalogue", action: onBrowseCatalogue)
                    .psPrimary()
                Button("My Slots", action: onOpenMySlots)
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .psTextStyle(.caption)
                    .foregroundStyle(.psCyan)
                    .accessibilityHidden(true)
                Text("Secure M-PESA checkout  ·  Instant delivery  ·  Encrypted vault")
                    .psTextStyle(.caption)
                    .foregroundStyle(.psMuted)
            }
            .accessibilityLabel("Secure M-PESA checkout, instant delivery, encrypted vault")
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.psPrimary.opacity(0.16), Color.psSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    // MARK: - Live stats, live data only

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isFirstLoad {
                PSSkeletonStats(count: 3)
            } else {
                if appState.liveState == .offline {
                    PSOfflineBanner(message: "")
                }
                HStack(spacing: 12) {
                    statTile(value: "\(appState.platformCount)", label: "Platforms", systemImage: "square.grid.2x2.fill")
                    if appState.liveState == .live, let total = appState.liveTotalSlots {
                        statTile(value: "\(total)", label: "Slots in rotation", systemImage: "square.stack.3d.up.fill")
                    }
                    statTile(value: "\(slotsAvailableNow)", label: "Slots available", systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    private func statTile(value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.psIcon)
                .foregroundStyle(.psCyan)
                .accessibilityHidden(true)
            Text(value)
                .psTextStyle(.title)
            Text(label)
                .psTextStyle(.caption)
                .foregroundStyle(.psMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// Signed-in strip: your own active slots, from the live list.
    @ViewBuilder
    private var mySlotsStrip: some View {
        if appState.isLoggedIn, !appState.liveSubscriptions.isEmpty {
            Button(action: onOpenMySlots) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.psIcon)
                        .foregroundStyle(.psCyan)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You have \(activeSlotCount) active slot\(activeSlotCount == 1 ? "" : "s")")
                            .psTextStyle(.headline)
                        Text("Tap to see your vault details and renewal dates.")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.psIconSmall)
                        .foregroundStyle(.psMuted)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.psBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("You have \(activeSlotCount) active slots. Open My Slots.")
        }
    }

    // MARK: - Featured platforms, real logos

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "Featured platforms", actionLabel: "See all") {
                onBrowseCatalogue()
            }
            if isFirstLoad {
                PSSkeletonGrid(count: 4)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(featuredPlatforms) { platform in
                        SlotCard(
                            platform: platform,
                            isOnWaitlist: appState.waitlist.contains(platform.id),
                            onWaitlistTap: { toggleWaitlist(for: platform) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedPlatform = platform }
                    }
                }
            }
        }
    }

    // MARK: - Going fast, from live stock

    @ViewBuilder
    private var goingFastSection: some View {
        if !isFirstLoad, !goingFastPlatforms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PSSectionHeader(title: "Going fast")
                PSCard {
                    VStack(spacing: 0) {
                        ForEach(Array(goingFastPlatforms.enumerated()), id: \.element.id) { index, platform in
                            Button {
                                selectedPlatform = platform
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .psTextStyle(.headline)
                                        .foregroundStyle(.psCyan)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    PlatformLogoView(platform: platform, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(platform.name)
                                            .psTextStyle(.headline)
                                        Text(platform.formattedPrice + " per slot")
                                            .psTextStyle(.caption)
                                            .foregroundStyle(.psMuted)
                                    }
                                    Spacer()
                                    PSStatusPill(
                                        text: platform.slotsLeft == 1 ? "Last slot" : "\(platform.slotsLeft) left",
                                        systemImage: "exclamationmark.circle.fill",
                                        tint: .psAmber
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.psIconSmall)
                                        .foregroundStyle(.psMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(platform.name), \(platform.formattedPrice) per slot, \(platform.slotsLeft) slots left")
                            if index < goingFastPlatforms.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - How it works, 3 steps

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "How it works")
            PSCard {
                VStack(alignment: .leading, spacing: 0) {
                    howStep(
                        number: "1",
                        icon: "person.crop.circle.badge.plus",
                        title: "Create Account",
                        text: "Create your PremiumSlots account in a minute."
                    )
                    Divider()
                        .padding(.vertical, 12)
                    howStep(
                        number: "2",
                        icon: "creditcard.fill",
                        title: "Pay via M-PESA",
                        text: "Send the exact amount by M-PESA and keep your transaction code."
                    )
                    Divider()
                        .padding(.vertical, 12)
                    howStep(
                        number: "3",
                        icon: "lock.shield.fill",
                        title: "Instant Access",
                        text: "Submit your code and get your own profile through the encrypted vault."
                    )
                }
            }
        }
    }

    private func howStep(number: String, icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .psTextStyle(.headline)
                .foregroundStyle(.psCyan)
                .frame(width: 32, height: 32)
                .background(Color.psPrimarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.psIcon)
                        .foregroundStyle(.psCyan)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(title)
                        .psTextStyle(.headline)
                }
                Text(text)
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
            }
        }
    }

    // MARK: - Why PremiumSlots (factual service copy only)

    private var whyChooseUsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "Why PremiumSlots")
            VStack(alignment: .leading, spacing: 12) {
                whyRow(
                    icon: "lock.shield.fill",
                    title: "Your own profile",
                    text: "Every slot is your own profile on the shared account. 1 slot = 1 device."
                )
                whyRow(
                    icon: "checkmark.seal.fill",
                    title: "Verified by hand",
                    text: "Every M-PESA code is checked by the team before a slot is approved."
                )
                whyRow(
                    icon: "tag.fill",
                    title: "Fair monthly prices",
                    text: "One shared slot costs a fraction of a full subscription, every month."
                )
            }
            .padding(14)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.psBorder, lineWidth: 1)
            )
        }
    }

    private func whyRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.psIcon)
                .foregroundStyle(.psCyan)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .psTextStyle(.headline)
                Text(text)
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
            }
        }
    }

    // MARK: - FAQ teaser

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "Questions")
            PSCard {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("How do I pay?") {
                        Text("Send the exact amount by M-PESA to PayBill 400200, account 1192526, then submit the 10-letter-and-number code from your confirmation message in checkout.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psDim)
                    }
                    .psTextStyle(.headline)
                    Divider()
                    DisclosureGroup("When do I get my details?") {
                        Text("Once the team verifies your code, your slot moves to Active in My Slots and your vault details appear there.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psDim)
                    }
                    .psTextStyle(.headline)
                    Divider()
                    DisclosureGroup("Can I use my slot on more than one device?") {
                        Text("No. 1 slot = 1 device. Use it on your own device only.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psDim)
                    }
                    .psTextStyle(.headline)
                }
            }
        }
    }

    // MARK: - Support (real WhatsApp channel)

    private var supportSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Need help?")
                    .psTextStyle(.headline)
                Text("Something not working with a slot, or a question before you buy? The support team can help.")
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
                Link(destination: PSContact.whatsAppSupportURL) {
                    Label("WhatsApp support", systemImage: "message.fill")
                        .psTextStyle(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.psCyan)
                .accessibilityLabel("WhatsApp support, \(PSContact.whatsAppDisplayNumber)")
                HStack(spacing: 16) {
                    NavigationLink {
                        TicketsRootView()
                    } label: {
                        Label("Support tickets", systemImage: "envelope.fill")
                            .psTextStyle(.caption)
                    }
                    NavigationLink {
                        HelpRootView()
                    } label: {
                        Label("Help centre", systemImage: "questionmark.circle.fill")
                            .psTextStyle(.caption)
                    }
                }
                .padding(.top, 4)
                Button("More support options", action: onOpenSupport)
                    .psTextStyle(.caption)
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
