import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View Model

@MainActor
final class InvoiceDetailViewModel: ObservableObject {
    @Published private(set) var invoice: FlexiBeeInvoice
    @Published private(set) var lineItems: [FlexiBeeInvoiceItem] = []
    @Published private(set) var isLoadingItems = false
    @Published private(set) var loadError: String?
    @Published private(set) var isUpdatingStatus = false
    @Published private(set) var statusUpdateError: String?
    @Published private(set) var isDeleting = false
    @Published private(set) var deleteError: String?

    // Sheet / alert presentation — owned by ViewModel so the view has no @State
    @Published var showEdit = false
    @Published var showStatusAlert = false
    @Published var showStatusError = false
    @Published var showDeleteAlert = false
    @Published var showDeleteError = false
    @Published private(set) var pendingStatus: PaymentStatus?

    let salesViewModel: SalesViewModel
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel, router: AppRouter) {
        self.invoice = invoice
        self.salesViewModel = salesViewModel
        self.router = router

        // Forward FlexiBeeService changes so itemsSection re-renders when stock data arrives
        FlexiBeeService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var canEdit: Bool {
        AuthService.shared.canEditInvoice || invoice.paymentStatus != .paid
    }

    var canDelete: Bool {
        AuthService.shared.canDeleteInvoice
    }

    // Looks up a stock item for a NavigationLink in the items list
    func stockItem(for cenikCode: String) -> FlexiBeeStockWithPrice? {
        FlexiBeeService.shared.stockWithPrices[id: cenikCode]
    }

    func load() async {
        isLoadingItems = true
        loadError = nil
        do {
            let raw = try await FlexiBeeService.shared.fetchLineItemsForInvoice(invoice.id)
            lineItems = raw.filter { !$0.productName.isEmpty && $0.quantity > 0 }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingItems = false
    }

    func selectPendingStatus(_ status: PaymentStatus) {
        pendingStatus = status
        showStatusAlert = true
    }

    func confirmStatusChange() {
        guard let s = pendingStatus else { return }
        pendingStatus = nil
        Task { await setPaymentStatus(s) }
    }

    func cancelStatusChange() {
        pendingStatus = nil
    }

    func setPaymentStatus(_ status: PaymentStatus) async {
        isUpdatingStatus = true
        statusUpdateError = nil
        do {
            try await FlexiBeeService.shared.updateInvoicePaymentStatus(id: invoice.id, status: status)
            if let updated = try? await FlexiBeeService.shared.fetchSingleInvoice(id: invoice.id) {
                invoice = updated
            }
            Task { await salesViewModel.forceSync() }
        } catch {
            statusUpdateError = error.localizedDescription
            showStatusError = true
        }
        isUpdatingStatus = false
    }

    func delete() async {
        isDeleting = true
        deleteError = nil
        do {
            try await salesViewModel.deleteInvoice(id: invoice.id)
            router.pop()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
        isDeleting = false
    }
}
