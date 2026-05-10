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
                if auth.canViewAnalytics {
                    AnalyticsTabView(viewModel: salesViewModel)
                        .tabItem { Label(String.sales_analytics, systemImage: "chart.line.uptrend.xyaxis") }
                }
                if auth.canViewInvoices {
                    InvoicesTabView(viewModel: salesViewModel)
                        .tabItem { Label(String.sales_invoices, systemImage: "doc.text") }
                }
                if auth.canViewUsers {
                    UsersView()
                        .tabItem { Label(String.users_nav_title, systemImage: "person.2.fill") }
                }
            }

            if showGreeting {
                Text(localeFlag)
                    .font(.system(size: 48))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .cornerRadius(16)
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

    private var localeFlag: String {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        let regionCode: String
        switch lang.prefix(2) {
        case "uk": regionCode = "UA"
        case "ru": regionCode = "RU"
        case "cs": regionCode = "CZ"
        default:   regionCode = Locale(identifier: lang).region?.identifier ?? "US"
        }
        let base: UInt32 = 127397
        return regionCode.unicodeScalars
            .compactMap { Unicode.Scalar(base + $0.value).map(String.init) }
            .joined()
    }
}
