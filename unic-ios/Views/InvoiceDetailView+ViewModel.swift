import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View Model

/// Drives the invoice detail screen.
///
/// ## Payment + stock movement flow
///
/// **No bundles (common case):**
///   "Paid" button → auto-creates stock movement → changes status to paid in one tap.
///
/// **Bundles present:**
///   "Stock Movement" button → opens StockMovementView sheet where the user manually adds
///   bundle components → on submit, `stockMovementCreated` is set and persisted →
///   "Paid" button appears → changes status only (movement already done).
///
/// `autoShowMovement = true` (set after invoice creation) only triggers the bundle sheet
/// for invoices that have starter-kit items. Non-bundle invoices do nothing on creation —
/// movement happens on payment.
///
/// `stockMovementCreated` is persisted to UserDefaults so it survives navigation.
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
    @Published private(set) var stockMovementCreated: Bool

    private let autoShowMovement: Bool

    let salesViewModel: SalesViewModel
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []

    // MARK: - Persistence

    private static let udKey = "stock_movement_done_ids"

    private static func isMovementDone(for invoiceId: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: udKey) ?? []).contains(invoiceId)
    }

    private static func markMovementDone(for invoiceId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: udKey) ?? []
        guard !ids.contains(invoiceId) else { return }
        ids.append(invoiceId)
        UserDefaults.standard.set(ids, forKey: udKey)
    }

    // MARK: - Init

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel, router: AppRouter, autoShowMovement: Bool = false) {
        self.invoice = invoice
        self.salesViewModel = salesViewModel
        self.router = router
        self.autoShowMovement = autoShowMovement
        self.stockMovementCreated = Self.isMovementDone(for: invoice.id)

        FlexiBeeService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Permissions

    var canEdit: Bool {
        AuthService.shared.canEditInvoice || invoice.paymentStatus != .paid
    }

    var canDelete: Bool {
        AuthService.shared.canDeleteInvoice
    }

    var canManageStock: Bool {
        AuthService.shared.canCreateStockMovement && invoice.paymentStatus != .paid
    }

    /// True when at least one line item is a bundle/starter-kit.
    /// Computed from live lineItems, so it's valid only after `load()` completes.
    var hasBundles: Bool {
        let codes = FirebaseService.shared.bundleCodes
        return lineItems.contains { codes.contains($0.productCode) }
    }

    /// True when the "Stock Movement" button should be shown.
    /// Only bundle invoices need the manual sheet; non-bundle invoices go straight to payment.
    var needsBundleMovement: Bool {
        canManageStock && hasBundles && !stockMovementCreated
    }

    // MARK: - Stock item lookup

    func stockItem(for cenikCode: String) -> FlexiBeeStockWithPrice? {
        FlexiBeeService.shared.stockWithPrices[id: cenikCode]
    }

    // MARK: - Load

    func load() async {
        isLoadingItems = true
        loadError = nil
        do {
            async let rawItems = FlexiBeeService.shared.fetchLineItemsForInvoice(invoice.id)
            async let movementExists = FlexiBeeService.shared.hasStockMovement(for: invoice.invoiceNumber)
            let (items, exists) = try await (rawItems, movementExists)
            lineItems = items.filter { !$0.productName.isEmpty && $0.quantity > 0 }
            if exists { setStockMovementDone() }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingItems = false
        // After invoice creation: show bundle sheet if needed; non-bundle movement happens on payment
        if autoShowMovement, hasBundles { openStockMovement() }
    }

    // MARK: - Stock Movement

    private func setStockMovementDone() {
        stockMovementCreated = true
        Self.markMovementDone(for: invoice.id)
    }

    /// Silently creates a stock movement in FlexiBee for all non-bundle line items.
    /// Sets `stockMovementCreated` on success; opens the manual sheet on API failure.
    private func autoCreateStockMovement() async {
        let bundleCodes = FirebaseService.shared.bundleCodes
        let lines: [NewStockMovementLine] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty,
                  !bundleCodes.contains(item.productCode) else { return nil }
            return NewStockMovementLine(productCode: "code:\(item.productCode)", quantity: item.quantity)
        }
        guard !lines.isEmpty else { setStockMovementDone(); return }

        let movement = NewStockMovement(
            documentType: "code:STANDARD",
            description: "Vydej k \(invoice.invoiceNumber)",
            lines: lines
        )
        do {
            try await FlexiBeeService.shared.createStockMovement(movement)
            setStockMovementDone()
        } catch {
            // Fall back to manual sheet so the user can retry
            openStockMovement()
        }
    }

    func openStockMovement() {
        let bundleCodes = FirebaseService.shared.bundleCodes

        let regularDrafts: [InvoiceLineItemDraft] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty,
                  !bundleCodes.contains(item.productCode) else { return nil }
            var draft = InvoiceLineItemDraft()
            draft.name = item.productName
            draft.productCode = item.productCode
            draft.quantity = String(format: "%g", item.quantity)
            return draft
        }

        let bundleSections: [BundleSection] = lineItems.compactMap { item in
            guard bundleCodes.contains(item.productCode) else { return nil }
            return BundleSection(bundleName: item.productName, bundleCode: item.productCode, components: [])
        }

        pendingMovement = PendingMovement(
            invoiceId: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            items: regularDrafts,
            bundleSections: bundleSections,
            onMovementCreated: { [weak self] in self?.setStockMovementDone() }
        )
        showStockMovement = true
    }

    // MARK: - Payment status

    func selectPendingStatus(_ status: PaymentStatus) {
        pendingStatus = status
        showStatusAlert = true
    }

    func confirmStatusChange() {
        guard let s = pendingStatus else { return }
        pendingStatus = nil
        let task = Task {
            // Non-bundle invoices: auto-create movement as part of the payment action
            if s == .paid, self.canManageStock, !self.hasBundles, !self.stockMovementCreated {
                await self.autoCreateStockMovement()
                // If auto-creation failed, the manual sheet is now open — don't proceed to payment
                guard self.stockMovementCreated else { return }
            }
            await self.setPaymentStatus(s)
        }
        tasks.append(task)
    }

    func cancelStatusChange() {
        pendingStatus = nil
    }

    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func setPaymentStatus(_ status: PaymentStatus) async {
        isUpdatingStatus = true
        statusUpdateError = nil
        do {
            try await FlexiBeeService.shared.updateInvoicePaymentStatus(id: invoice.id, status: status)
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
