import SwiftUI

// MARK: - ContentView, v4 (v6 deep links)
// New tab bar: Home, Catalogue, My Slots, Wallet, Settings.
// How it works lives inside Home (and Help); Admin lives in Settings
// (Admin dashboard / Admin sign-in) and is NOT on the tab bar.
// Every tab root sits in its own NavigationStack, so swipe-back works
// natively on every push, and every sheet has a dismiss control.
// Swiping left/right on the tab content moves between tabs.
//
// Deep links (v6): NotificationsRootView posts a PSDeepLink when a
// notification is tapped. This view is the only place that owns the
// tab bar, so it handles the routing: tab destinations switch tabs
// (a subscription id is handed to MySlotsView, which opens the
// detail sheet for that subscription once it is loaded), and
// destinations with no tab (tickets, dashboard, gift cards, help,
// wishlist) are presented as sheets over the tabs. No tap lands
// nowhere: an unknown link falls back to Home.

enum PSTab: String, CaseIterable {
    case home, catalogue, mySlots, wallet, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .catalogue: return "Catalogue"
        case .mySlots: return "My Slots"
        case .wallet: return "Wallet"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .catalogue: return "square.grid.2x2.fill"
        case .mySlots: return "lock.shield.fill"
        case .wallet: return "wallet.pass.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: PSTab = .home
    @State private var deepLinkSubscriptionId: Int?
    @State private var presentedLink: PSDeepLink?

    var body: some View {
        // Safe area: the TabView and every tab root NavigationStack
        // respect the top safe area, so content starts below the
        // notch and Dynamic Island on first appearance and only
        // scrolls under the bar once the user scrolls. No
        // ignoresSafeArea is used on the top anywhere in this view
        // or in HomeView and MySlotsView; the only ignoresSafeArea
        // in the owned files is the full-screen loader background
        // in PSLoaderView, whose content is centred and never sits
        // under the notch. The background colour extends under the
        // tab bar and the home indicator through psScreenBackground
        // on each tab root, so the app is full screen edge to edge.
        TabView(selection: $selectedTab) {
            HomeView(
                onBrowseCatalogue: { selectedTab = .catalogue },
                onOpenMySlots: { selectedTab = .mySlots },
                onOpenSupport: { selectedTab = .settings }
            )
            .tabItem { Label(PSTab.home.title, systemImage: PSTab.home.systemImage) }
            .tag(PSTab.home)

            CatalogView()
            .tabItem { Label(PSTab.catalogue.title, systemImage: PSTab.catalogue.systemImage) }
            .tag(PSTab.catalogue)

            MySlotsView(
                onBrowseCatalogue: { selectedTab = .catalogue },
                deepLinkSubscriptionId: $deepLinkSubscriptionId
            )
            .tabItem { Label(PSTab.mySlots.title, systemImage: PSTab.mySlots.systemImage) }
            .tag(PSTab.mySlots)

            WalletRootView()
            .tabItem { Label(PSTab.wallet.title, systemImage: PSTab.wallet.systemImage) }
            .tag(PSTab.wallet)

            SettingsView()
            .tabItem { Label(PSTab.settings.title, systemImage: PSTab.settings.systemImage) }
            .tag(PSTab.settings)
        }
        .tint(.psCyan)
        // Swipe between tabs: a horizontal drag that clearly dominates
        // the vertical movement moves to the next/previous tab.
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                    let tabs = PSTab.allCases
                    guard let index = tabs.firstIndex(of: selectedTab) else { return }
                    if dx < 0, index < tabs.count - 1 {
                        selectedTab = tabs[index + 1]
                    } else if dx > 0, index > 0 {
                        selectedTab = tabs[index - 1]
                    }
                }
        )
        // Onboarding gate, as on the web: after Clerk sign-in, if
        // WhatsApp or date of birth is missing, the user must finish
        // onboarding before using the app. Full-screen native form.
        .fullScreenCover(isPresented: $appState.needsOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .psDeepLink)) { note in
            guard let link = note.object as? PSDeepLink else { return }
            handleDeepLink(link)
        }
        .sheet(item: $presentedLink) { link in
            deepLinkSheet(link)
        }
    }

    private func handleDeepLink(_ link: PSDeepLink) {
        switch link {
        case .subscription(let subId):
            deepLinkSubscriptionId = subId
            selectedTab = .mySlots
        case .mySlots:
            selectedTab = .mySlots
        case .wallet:
            selectedTab = .wallet
        case .catalogue:
            selectedTab = .catalogue
        case .home:
            selectedTab = .home
        case .ticket, .dashboard, .giftCards, .help, .wishlist:
            presentedLink = link
        }
    }

    @ViewBuilder
    private func deepLinkSheet(_ link: PSDeepLink) -> some View {
        switch link {
        case .ticket(let ticketId):
            NavigationStack {
                TicketsRootView(highlightTicketId: ticketId)
            }
        case .dashboard:
            NavigationStack {
                DashboardRootView()
            }
        case .giftCards:
            GiftCardsRootView()
        case .help:
            NavigationStack {
                HelpRootView()
            }
        case .wishlist:
            NavigationStack {
                WishlistRootView()
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
