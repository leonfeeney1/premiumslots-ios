import SwiftUI

// MARK: - Home, v4
// First tab. Hero with the real PremiumSlots logo lockup, live stats
// from the catalogue API (platforms, slots in rotation, slots
// available now), a live catalogue preview, a short How it works
// summary, a why-choose-us section and a Support shortcut. Every
// number comes from the live API; while loading the ring spinner
// shows, and on failure an error state with retry shows. No saved
// or invented numbers are shown as live.
//
// Wiring note: ContentView is owned by another agent. It should add
// this view as the first tab and pass onBrowseCatalogue (switch to
// the Catalogue tab) and onOpenSupport (switch to the Settings tab
// Support section). Until then both actions default to doing nothing.

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
                    previewSection
                    howItWorksSection
                    whyChooseUsSection
                    supportSection
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.psBackground)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
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

    private var previewPlatforms: [Platform] {
        let available = appState.platforms.filter { !$0.isSoldOut }
        return Array((available.isEmpty ? appState.platforms : available).prefix(4))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RealLogoView(size: 52)
                LogoLockupView(height: 36)
            }
            Text("Shared subscriptions, one slot at a time.")
                .font(.psTitle)
            Text("Premium streaming, music, design and learning accounts, shared fairly. Pay by M-PESA and get your own profile.")
                .font(.psBody)
                .foregroundStyle(.psMuted)
            Button("Browse the catalogue", action: onBrowseCatalogue)
                .psPrimary()
        }
    }

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
            HStack(spacing: 12) {
                statTile(value: "\(appState.platformCount)", label: "Platforms")
                if let total = appState.liveTotalSlots {
                    statTile(value: "\(total)", label: "Slots in rotation")
                }
                statTile(value: "\(slotsAvailableNow)", label: "Slots available")
            }
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "Popular right now", actionLabel: "See all") {
                onBrowseCatalogue()
            }
            if appState.liveState == .live || !isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(previewPlatforms) { platform in
                            SlotCard(
                                platform: platform,
                                isOnWaitlist: appState.waitlist.contains(platform.id),
                                onWaitlistTap: {
                                    if appState.waitlist.contains(platform.id) {
                                        appState.leaveWaitlist(platformId: platform.id)
                                    } else {
                                        appState.joinWaitlist(platformId: platform.id)
                                    }
                                }
                            )
                            .frame(width: 180)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedPlatform = platform }
                        }
                    }
                }
            }
        }
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSSectionHeader(title: "How it works")
            VStack(spacing: 12) {
                howStep(
                    number: "1",
                    icon: "person.crop.circle.badge.plus",
                    title: "Create Account",
                    text: "Create your PremiumSlots account in a minute."
                )
                howStep(
                    number: "2",
                    icon: "creditcard.fill",
                    title: "Pay via M-PESA",
                    text: "Send the exact amount by M-PESA and keep your transaction code."
                )
                howStep(
                    number: "3",
                    icon: "lock.shield.fill",
                    title: "Instant Access",
                    text: "Submit your code and get your own profile through the encrypted vault."
                )
            }
        }
    }

    private func howStep(number: String, icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.psCyan)
                .frame(width: 32, height: 32)
                .background(Color.psPrimarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.psCyan)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.psHeadline)
                Text(text)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

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
                .font(.system(size: 20))
                .foregroundStyle(.psCyan)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.psHeadline)
                Text(text)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
    }

    private var supportSection: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Need help?")
                    .font(.psHeadline)
                Text("Something not working with a slot, or a question before you buy? The support team can help.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Button("Get support", action: onOpenSupport)
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
