import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View Model

/// Drives the invoice detail screen: loads line items, manages stock movement flow,
/// handles payment status updates, and delegates deletion to `SalesViewModel`.
///
/// All sheet/alert presentation state lives here (not in the View) per the MVVM rule.
/// `canManageStock` gates the stock movement button — once `stockMovementCreated` is true
/// the green "Paid" button appears instead.
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
    @Published var showStockMovement = false
    @Published private(set) var pendingMovement: PendingMovement?
    @Published private(set) var stockMovementCreated = false

    private let autoShowMovement: Bool

    let salesViewModel: SalesViewModel
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel, router: AppRouter, autoShowMovement: Bool = false) {
        self.invoice = invoice
        self.salesViewModel = salesViewModel
        self.router = router
        self.autoShowMovement = autoShowMovement

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

    var canManageStock: Bool {
        AuthService.shared.canCreateStockMovement && invoice.paymentStatus != .paid
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
        if autoShowMovement { await triggerStockMovement() }
    }

    // MARK: - Stock Movement
    //
    // Stock movement flow (triggered after invoice creation via autoShowMovement = true,
    // or manually via the blue "Stock movement" button while invoice is unpaid):
    //
    // 1. triggerStockMovement() checks whether any invoice line item is a bundle/starter kit.
    //    Bundle codes are maintained in Firestore at config/bundleCodes and loaded at app startup.
    //
    // 2a. No bundles → autoCreateStockMovement():
    //     All stock items have a ceník ref and none are bundles, so the movement is created
    //     silently via the FlexiBee API. stockMovementCreated = true unlocks the "Paid" button.
    //     On API failure, falls back to manual sheet so the user can retry.
    //
    // 2b. Bundles present → openStockMovement():
    //     Shows StockMovementView sheet pre-filled with regular stock items only.
    //     The user must manually add the individual bundle components (which have no stock record
    //     in FlexiBee and are not tracked via ceník). stockMovementCreated = true is set via
    //     PendingMovement.onMovementCreated callback after a successful submit.
    //
    // Items are eligible for stock movement only when:
    //   - item.stockCode != nil  (has an explicit ceník reference — real stock item)
    //   - productCode not in bundleCodes  (not a starter-kit bundle)

    private func triggerStockMovement() async {
        let bundleCodes = FirebaseService.shared.bundleCodes
        let hasBundles = lineItems.contains { bundleCodes.contains($0.productCode) }
        if hasBundles {
            openStockMovement()
        } else {
            await autoCreateStockMovement()
        }
    }

    private func autoCreateStockMovement() async {
        let bundleCodes = FirebaseService.shared.bundleCodes
        // Use productCode (kod) directly — cenikRef may be absent in API response but kod is always present
        let lines: [NewStockMovementLine] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty,
                  !bundleCodes.contains(item.productCode) else { return nil }
            return NewStockMovementLine(productCode: "code:\(item.productCode)", quantity: item.quantity)
        }
        guard !lines.isEmpty else {
            stockMovementCreated = true
            return
        }
        let movement = NewStockMovement(
            documentType: "code:STANDARD",
            description: "Vydej k \(invoice.invoiceNumber)",
            lines: lines
        )
        do {
            try await FlexiBeeService.shared.createStockMovement(movement)
            stockMovementCreated = true
        } catch {
            openStockMovement()
        }
    }

    func openStockMovement() {
        let bundleCodes = FirebaseService.shared.bundleCodes

        // Regular items: all non-empty, non-bundle invoice items — use productCode directly
        let regularDrafts: [InvoiceLineItemDraft] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty,
                  !bundleCodes.contains(item.productCode) else { return nil }
            var draft = InvoiceLineItemDraft()
            draft.name = item.productName
            draft.productCode = item.productCode
            draft.quantity = String(format: "%g", item.quantity)
            return draft
        }

        // Bundle sections: one section per bundle item, starts empty — user adds components
        let bundleSections: [BundleSection] = lineItems.compactMap { item in
            guard bundleCodes.contains(item.productCode) else { return nil }
            return BundleSection(bundleName: item.productName, bundleCode: item.productCode, components: [])
        }

        pendingMovement = PendingMovement(
            invoiceId: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            items: regularDrafts,
            bundleSections: bundleSections,
            onMovementCreated: { [weak self] in self?.stockMovementCreated = true }
        )
        showStockMovement = true
    }

    func selectPendingStatus(_ status: PaymentStatus) {
        pendingStatus = status
        showStatusAlert = true
    }

    func confirmStatusChange() {
        guard let s = pendingStatus else { return }
        pendingStatus = nil
        let task = Task { await setPaymentStatus(s) }
        tasks.append(task)
    }

    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func cancelStatusChange() {
        pendingStatus = nil
    }

    func setPaymentStatus(_ status: PaymentStatus) async {
        isUpdatingStatus = true
        statusUpdateError = nil
        do {
            try await FlexiBeeService.shared.updateInvoicePaymentStatus(id: invoice.id, status: status)
            // Refetch is a UI refresh only — status update already succeeded
            do {
                if let updated = try await FlexiBeeService.shared.fetchSingleInvoice(id: invoice.id) {
                    invoice = updated
                }
            } catch {
                // Non-critical: invoice will refresh via forceSync below
            }
            await salesViewModel.forceSync()
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
