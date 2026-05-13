import SwiftUI

struct MainScreen: View {
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var salonsViewModel = SalonsViewModel()
    @StateObject private var salesViewModel = SalesViewModel()
    @StateObject private var planViewModel = PlanViewModel()
    @State private var showGreeting = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                SalonListScreen(viewModel: salonsViewModel)
                    .tabItem { Label("Salons", systemImage: "storefront") }
                PromosScreen()
                    .tabItem { Label(String(localized: "promos_nav_title"), systemImage: "tag") }
                FlexiBeeScreen()
                    .tabItem { Label(String.stock_nav_title, systemImage: "shippingbox") }
                if auth.canViewSales {
                    SalesScreen(viewModel: salesViewModel)
                        .tabItem { Label(String.sales_nav_title, systemImage: "chart.line.uptrend.xyaxis") }
                }
                if auth.canViewUsers {
                    UsersScreen()
                        .tabItem { Label(String.users_nav_title, systemImage: "person.2.fill") }
                }
                ProfileScreen()
                    .tabItem { Label(String.profile_nav_title, systemImage: "person.circle") }
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
