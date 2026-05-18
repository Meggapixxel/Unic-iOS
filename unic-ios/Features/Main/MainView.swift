import ComposableArchitecture
import SwiftUI

/// Four-tab main interface wrapped in a single root NavigationStack so that all tabs share one
/// navigation path. This allows the tab bar to animate in/out smoothly on iOS 18+ without the
/// `.toolbar(.hidden, for: .tabBar)` glitches that occur with per-tab NavigationStacks.
struct MainView: View {
    @Bindable var store: StoreOf<MainFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
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

                TCAPlankBannerView(store: store.scope(state: \.planBanner, action: \.planBanner))
                    .padding(.top, 60)
                    .allowsHitTesting(false)
            }
        } destination: { pathStore in
            switch pathStore.case {
            case let .salonDetail(detailStore):
                SalonDetailView(store: detailStore)
            case let .testDrive(tdStore):
                TestDriveView(store: tdStore)
            case let .productDetail(productStore):
                ProductDetailView(store: productStore)
            case let .catalog(catalogStore):
                CatalogView(store: catalogStore)
            case let .userActivity(activityStore):
                UserActivityView(store: activityStore)
            case let .sales(salesStore):
                SalesView(store: salesStore)
            case let .invoiceDetail(detailStore):
                InvoiceDetailView(store: detailStore)
            case let .allTopClients(clientsStore):
                AllTopClientsView(store: clientsStore)
            case let .allTopProducts(productsStore):
                AllTopProductsView(store: productsStore)
            case let .users(usersStore):
                UsersView(store: usersStore)
            case let .plans(plansStore):
                PlansView(store: plansStore)
            case let .clientDetail(clientStore):
                ClientDetailView(store: clientStore)
            }
        }
        .task { store.send(.onAppear) }
    }
}
