import SwiftUI

struct AppNavigationStack<Content: View>: View {
    var router: AppRouter
    var salesViewModel: SalesViewModel? = nil
    @ViewBuilder let content: Content

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            content
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .product(let item):
                        FlexiBeeProductDetailScreen(item: item)
                    case .invoice(let invoice):
                        if let vm = salesViewModel {
                            InvoiceDetailScreen(invoice: invoice, salesViewModel: vm, router: router)
                        }
                    case .allTopProducts:
                        if let vm = salesViewModel {
                            AllTopProductsScreen(viewModel: vm, router: router)
                        }
                    case .allTopClients:
                        if let vm = salesViewModel {
                            AllTopClientsScreen(viewModel: vm)
                        }
                    case .userActivity(let user):
                        UserActivityScreen(user: user)
                    case .stockChecklist:
                        StockChecklistScreen()
                    case .plans:
                        PlansScreen()
                    case .sales:
                        if let vm = salesViewModel {
                            SalesContentView(viewModel: vm, router: router)
                        }
                    case .users:
                        UsersContentView()
                    }
                }
        }
    }
}
