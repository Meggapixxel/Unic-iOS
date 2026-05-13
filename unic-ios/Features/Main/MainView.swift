import ComposableArchitecture
import SwiftUI

struct MainView: View {
    @Bindable var store: StoreOf<MainFeature>

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $store.selectedTab) {
                SalonsView(store: store.scope(state: \.salons, action: \.salons))
                    .tabItem { Label("Salons", systemImage: "storefront") }
                    .tag(MainFeature.State.Tab.salons)

                PromosView(store: store.scope(state: \.promos, action: \.promos))
                    .tabItem { Label(String.promos_nav_title, systemImage: "tag") }
                    .tag(MainFeature.State.Tab.promos)

                StockView(store: store.scope(state: \.stock, action: \.stock))
                    .tabItem { Label(String.stock_nav_title, systemImage: "shippingbox") }
                    .tag(MainFeature.State.Tab.stock)

                ProfileView(store: store.scope(state: \.profile, action: \.profile))
                    .tabItem { Label(String.profile_nav_title, systemImage: "person.circle") }
                    .tag(MainFeature.State.Tab.profile)
            }

            VStack(spacing: 0) {
                PlanBannerView(store: store.scope(state: \.planBanner, action: \.planBanner))

                if store.showGreeting {
                    Text("👋 \(store.currentUser.firstName)")
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
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: store.showGreeting)
        .task { store.send(.onAppear) }
    }
}
