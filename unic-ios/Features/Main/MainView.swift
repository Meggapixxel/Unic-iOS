import ComposableArchitecture
import SwiftUI

/// Four-tab main interface with an overlaid plan-progress banner driven by ``MainFeature``.
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

            /// Floating plan banner rendered above all tabs; hit-testing disabled so it never intercepts tab gestures.
            TCAPlankBannerView(store: store.scope(state: \.planBanner, action: \.planBanner))
                .padding(.top, 60)
                .allowsHitTesting(false)
        }
        .task { store.send(.onAppear) }
    }
}
