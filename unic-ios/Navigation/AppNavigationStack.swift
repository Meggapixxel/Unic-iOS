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
                        FlexiBeeProductDetailView(item: item)
                    case .invoice(let invoice):
                        if let vm = salesViewModel {
                            InvoiceDetailView(invoice: invoice, salesViewModel: vm, router: router)
                        }
                    case .allTopProducts:
                        if let vm = salesViewModel {
                            AllTopProductsView(viewModel: vm, router: router)
                        }
                    case .allTopClients:
                        if let vm = salesViewModel {
                            AllTopClientsView(viewModel: vm)
                        }
                    case .invoiceWithMovement(let invoice):
                        if let vm = salesViewModel {
                            InvoiceDetailView(invoice: invoice, salesViewModel: vm, router: router, autoShowMovement: true)
                        }
                    }
                }
        }
    }
}
