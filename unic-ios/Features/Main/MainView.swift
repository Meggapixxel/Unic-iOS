import ComposableArchitecture
import SwiftUI

/// Four-tab main interface wrapped in a single root NavigationStack so that all tabs share one
/// navigation path. This allows the tab bar to animate in/out smoothly on iOS 18+ without the
/// `.toolbar(.hidden, for: .tabBar)` glitches that occur with per-tab NavigationStacks.
struct MainView: View {
    @Bindable var store: StoreOf<MainFeature>

    var body: some View {
        let salonsView  = SalonsView(store: store.scope(state: \.salons,  action: \.salons))
        let promosView  = PromosView(store: store.scope(state: \.promos,  action: \.promos))
        let stockView   = StockView(store: store.scope(state: \.stock,   action: \.stock))
        let profileView = ProfileView(store: store.scope(state: \.profile, action: \.profile))

        let currentTitle: String = {
            switch store.selectedTab {
            case .salons:  salonsView.tabTitle
            case .promos:  promosView.tabTitle
            case .stock:   stockView.tabTitle
            case .profile: profileView.tabTitle
            }
        }()

        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ZStack(alignment: .top) {
                TabView(selection: $store.selectedTab) {
                    salonsView
                        .tabItem { Label("Salons", systemImage: "storefront") }
                        .tag(MainFeature.State.Tab.salons)

                    promosView
                        .tabItem { Label(String.promos_nav_title, systemImage: "tag") }
                        .tag(MainFeature.State.Tab.promos)

                    stockView
                        .tabItem { Label(String.stock_nav_title, systemImage: "shippingbox") }
                        .tag(MainFeature.State.Tab.stock)

                    profileView
                        .tabItem { Label(String.profile_nav_title, systemImage: "person.circle") }
                        .tag(MainFeature.State.Tab.profile)
                }

                TCAPlankBannerView(store: store.scope(state: \.planBanner, action: \.planBanner))
                    .padding(.top, 60)
                    .allowsHitTesting(false)
            }
            .searchableWhen(
                store.selectedTab == .salons,
                text: $store.salons.searchText,
                prompt: String.search_salons
            )
            .searchableWhen(
                store.selectedTab == .promos,
                text: $store.promos.searchText,
                prompt: String.search_promos
            )
            .searchableWhen(
                store.selectedTab == .stock,
                text: $store.stock.searchText,
                prompt: String.search_stock
            )
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.selectedTab == .salons {
                    salonsView.tabToolbar
                } else if store.selectedTab == .promos {
                    promosView.tabToolbar
                } else if store.selectedTab == .stock {
                    stockView.tabToolbar
                } else {
                    profileView.tabToolbar
                }
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

private extension View {
    @ViewBuilder
    func searchableWhen(_ condition: Bool, text: Binding<String>, prompt: String) -> some View {
        if condition {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
