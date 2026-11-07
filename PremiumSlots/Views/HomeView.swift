import SwiftUI

// MARK: - Home, v5
// First tab. One clean hero lockup: the real extended lockup only
// (shield plus wordmark once, in a single image), with a subtle
// gradient behind it. No second logo beside it and no stray favicon
// anywhere on Home. Live stats as elegant cards from the catalogue
// API (platforms, slots in rotation, slots available now), a
// featured platforms grid with real logos, a 3-step How it works
// visual, a why section with factual service copy only, and a
// support section with the real WhatsApp support link. Every number
// comes from the live API; while loading the ring spinner shows,
// and on failure an error state with retry shows. No saved or
// invented numbers are shown as live, and there are no invented
// quotes or testimonials anywhere on this screen.
//
// Safe area: the screen lives in a NavigationStack with an inline
// title, so content starts below the notch and Dynamic Island on
// first appearance and only scrolls under the bar once the user
// scrolls. The navigation bar background is an opaque brand colour
// so scrolled content never shows through behind the notch. No
// ignoresSafeArea is used on this screen.

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    var onBrowseCatalogue: () -> Void = {}
    var onOpenSupport: () -> Void = {}

    @State private var selectedPlatform: Platform?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    statsSection
                    featuredSection
                    howItWorksSection
                    whyChooseUsSection
                    supportSection
                }
                .padding(16)
            }
            .psHiddenScrollIndicators()
            .scrollDismissesKeyboard(.interactively)
            .background(Color.psBackground)
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        await appState.refreshCatalogue()
        if appState.liveState != .live {
            loadError = "The latest catalogue could not be loaded. Check your connection and try again."
        }
    }

    private var slotsAvailableNow: Int {
        appState.platforms.reduce(0) { $0 + $1.slotsLeft }
    }

    private var featuredPlatforms: [Platform] {
        let available = appState.platforms.filter { !$0.isSoldOut }
        return Array((available.isEmpty ? appState.platforms : available).prefix(6))
    }

    private func toggleWaitlist(for platform: Platform) {
        if appState.waitlist.contains(platform.id) {
            appState.leaveWaitlist(platformId: platform.id)
        } else {
            appState.joinWaitlist(platformId: platform.id)
        }
    }

    // MARK: - Hero: one lockup, once

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            LogoLockupView(height: 40)
            Text("Shared subscriptions, one slot at a time.")
                .psTextStyle(.title)
            Text("Premium streaming, music, design and learning accounts, shared fairly. Pay by M-PESA and get your own profile.")
                .psTextStyle(.body)
                .foregroundStyle(.psMuted)
            Button("Browse the catalogue", action: onBrowseCatalogue)
                .psPrimary()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.psPrimary.opacity(0.14), Color.psSurface],
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

    @ViewBuilder
    private var statsSection: some View {
        if isLoading && appState.liveState != .live {
            HStack {
                Spacer()
                PSRingSpinner(diameter: 32, lineWidth: 3)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if let loadError, appState.liveState != .live {
            PSErrorState(message: loadError) {
                Task { await load() }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
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

    // MARK: - Featured platforms, real logos

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "Featured platforms", actionLabel: "See all") {
                onBrowseCatalogue()
            }
            if appState.liveState == .live || !isLoading {
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
