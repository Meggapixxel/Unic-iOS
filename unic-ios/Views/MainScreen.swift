import SwiftUI

struct MainScreen: View {
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var salesViewModel = SalesViewModel()
    @State private var showGreeting = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                SalonListView()
                    .tabItem { Label("Salons", systemImage: "storefront") }
                FlexiBeeView()
                    .tabItem { Label(String.stock_nav_title, systemImage: "shippingbox") }
                if auth.canViewAnalytics || auth.canViewInvoices {
                    SalesTabView(viewModel: salesViewModel)
                        .tabItem { Label(String.sales_nav_title, systemImage: "chart.line.uptrend.xyaxis") }
                }
                if auth.canViewUsers {
                    UsersView()
                        .tabItem { Label(String.users_nav_title, systemImage: "person.2.fill") }
                }
                ProfileView()
                    .tabItem { Label(String.profile_nav_title, systemImage: "person.circle") }
            }

            if showGreeting, let user = auth.currentUser {
                Text("👋 \(user.firstName)")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { showGreeting = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showGreeting = false }
            }
        }
    }

}
