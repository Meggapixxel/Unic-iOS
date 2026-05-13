import SwiftUI

private enum MoreDestination {
    case sales, users, profile
}

struct MainScreen: View {
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var salonsViewModel = SalonsViewModel()
    @StateObject private var salesViewModel = SalesViewModel()
    @StateObject private var planViewModel = PlanViewModel()
    @State private var showGreeting = false
    @State private var selectedTab: Int = 0
    @State private var previousTab: Int = 0
    @State private var showMoreMenu = false
    @State private var activeMoreContent: MoreDestination? = nil

    var body: some View {
        ZStack {
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
                previousTab = old
                selectedTab = old
                showMoreMenu = true
            }

            // Plan banner + greeting
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .zIndex(1)

            // More drawer backdrop + panel
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activeMoreContent = dest
                    }
                }
            }
            .ignoresSafeArea()
            .offset(x: showMoreMenu ? 0 : 300)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showMoreMenu)
            .allowsHitTesting(showMoreMenu)
            .zIndex(11)

            // Selected More screen
            if let content = activeMoreContent {
                moreScreenView(for: content)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeMoreContent != nil)
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

    @ViewBuilder
    private func moreScreenView(for dest: MoreDestination) -> some View {
        ZStack(alignment: .topLeading) {
            switch dest {
            case .sales:   SalesScreen(viewModel: salesViewModel)
            case .users:   UsersScreen()
            case .profile: ProfileScreen()
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { activeMoreContent = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .padding(.top, 56)
            .padding(.leading, 16)
        }
    }
}

// MARK: - More Menu Panel

private struct MoreMenuPanel: View {
    let onSelect: (MoreDestination) -> Void

    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let user = auth.currentUser {
                Button { onSelect(.profile) } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(roleColor(user.role).opacity(0.15))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Text(initials(user))
                                    .font(.headline.bold())
                                    .foregroundStyle(roleColor(user.role))
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.fullName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(user.role.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 20)
                }
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

            Spacer()
        }
        .frame(width: 270)
        .background(.regularMaterial)
    }

    private func initials(_ user: AppUser) -> String {
        "\(user.firstName.prefix(1))\(user.lastName.prefix(1))".uppercased()
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
