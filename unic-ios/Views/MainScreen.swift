import SwiftUI

private enum MoreDestination: Identifiable {
    case sales, users, profile
    var id: Self { self }
}

struct MainScreen: View {
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var salonsViewModel = SalonsViewModel()
    @StateObject private var salesViewModel = SalesViewModel()
    @StateObject private var planViewModel = PlanViewModel()
    @State private var showGreeting = false
    @State private var selectedTab: Int = 0
    @State private var showMoreMenu = false
    @State private var moreDestination: MoreDestination? = nil

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                SalonListScreen(viewModel: salonsViewModel)
                    .tabItem { Label("Salons", systemImage: "storefront") }
                    .tag(0)
                PromosScreen()
                    .tabItem { Label(String(localized: "promos_nav_title"), systemImage: "tag") }
                    .tag(1)
                FlexiBeeScreen()
                    .tabItem { Label(String.stock_nav_title, systemImage: "shippingbox") }
                    .tag(2)
                if auth.isSales {
                    ProfileScreen()
                        .tabItem { Label(String.profile_nav_title, systemImage: "person.circle") }
                        .tag(3)
                } else {
                    Color.clear
                        .tabItem { Label("More", systemImage: "ellipsis") }
                        .tag(3)
                }
            }
            .onChange(of: selectedTab) { old, new in
                guard !auth.isSales, new == 3 else { return }
                selectedTab = old
                showMoreMenu = true
            }

            VStack(spacing: 0) {
                PlanBannerView(viewModel: planViewModel)
                    .animation(.spring(response: 0.4), value: planViewModel.shouldShow)

                if showGreeting, let user = auth.currentUser {
                    Text("👋 \(user.firstName)")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.thinMaterial)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 60)

            Color.black.opacity(showMoreMenu ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(showMoreMenu)
                .onTapGesture { showMoreMenu = false }
                .animation(.easeInOut(duration: 0.22), value: showMoreMenu)
                .zIndex(10)

            HStack(spacing: 0) {
                Spacer()
                MoreMenuPanel { dest in
                    showMoreMenu = false
                    moreDestination = dest
                }
            }
            .ignoresSafeArea()
            .offset(x: showMoreMenu ? 0 : 300)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showMoreMenu)
            .allowsHitTesting(showMoreMenu)
            .zIndex(11)
        }
        .sheet(item: $moreDestination) { dest in
            switch dest {
            case .sales:  SalesScreen(viewModel: salesViewModel)
            case .users:  UsersScreen()
            case .profile: ProfileScreen()
            }
        }
        .onAppear {
            planViewModel.load()
            withAnimation(.easeIn(duration: 0.3)) { showGreeting = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showGreeting = false }
            }
        }
        .onDisappear { planViewModel.cancel() }
    }
}

// MARK: - More Menu Panel

private struct MoreMenuPanel: View {
    let onSelect: (MoreDestination) -> Void

    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let user = auth.currentUser {
                VStack(alignment: .leading, spacing: 10) {
                    Circle()
                        .fill(roleColor(user.role).opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Text(initials(user))
                                .font(.title2.bold())
                                .foregroundStyle(roleColor(user.role))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.fullName)
                            .font(.headline)
                        Text(user.role.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 20)
            }

            Divider()

            if auth.canViewSales {
                MoreMenuRow(icon: "chart.line.uptrend.xyaxis", label: String.sales_nav_title) {
                    onSelect(.sales)
                }
            }
            if auth.canViewUsers {
                MoreMenuRow(icon: "person.2.fill", label: String.users_nav_title) {
                    onSelect(.users)
                }
            }
            MoreMenuRow(icon: "person.circle", label: String.profile_nav_title) {
                onSelect(.profile)
            }

            Spacer()
        }
        .frame(width: 270)
        .background(.regularMaterial)
    }

    private func initials(_ user: AppUser) -> String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin:   return .red
        case .manager: return .orange
        case .sales:   return .blue
        }
    }
}

private struct MoreMenuRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 28)
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        Divider().padding(.leading, 62)
    }
}
