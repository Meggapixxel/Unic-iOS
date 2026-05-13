import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View Model

/// Drives the invoice detail screen.
///
/// ## Payment + stock movement flow
///
/// **No bundles:** "Paid" → confirmation alert → status = paid.
///   FlexiBee auto-creates the stock movement at invoice creation time.
///
/// **Bundles present:** "Paid" → opens StockMovementScreen where user fills bundle components
///   → on submit, movement is created and status is set to paid automatically.
///   (FlexiBee cannot auto-create movements for bundles — no warehouse code.)
///
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

    @Published var showEdit = false
    @Published private(set) var editFormVM: InvoiceFormViewModel?
    @Published var showStatusAlert = false
    @Published var showStatusError = false
    @Published var showDeleteAlert = false
    @Published var showDeleteError = false
    @Published private(set) var pendingStatus: PaymentStatus?
    @Published var showStockMovement = false
    @Published private(set) var pendingMovement: PendingMovement?
    @Published var showPaymentMethodPicker = false
    @Published private(set) var pendingPaymentMethod: PaymentMethod?
    @Published private(set) var stockMovementCreated = false
    @Published private(set) var stockMovement: FlexiBeeStockMovement?
    @Published private(set) var stockMovementItems: [FlexiBeeStockMovementItem] = []

    @Published private(set) var cashReceiptId: String?
    @Published private(set) var isLoadingPDF = false
    @Published var pdfShareItem: PDFShareItem?

    private var pendingPayWhenLoaded = false

    let salesViewModel: SalesViewModel
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []

    // MARK: - Init

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel, router: AppRouter) {
        self.invoice = invoice
        self.salesViewModel = salesViewModel
        self.router = router

        FlexiBeeService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        FirebaseService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Permissions

    var canEdit: Bool {
        AuthService.shared.canEditInvoice && invoice.paymentStatus != .paid
    }

    var canDelete: Bool {
        AuthService.shared.canDeleteInvoice
    }

    var canManageStock: Bool {
        AuthService.shared.canCreateStockMovement && invoice.paymentStatus != .paid
    }

    var canEditStockMovement: Bool {
        AuthService.shared.canEditStockMovement && stockMovement != nil
    }

    /// True when at least one line item is a bundle/starter-kit.
    /// Computed from live lineItems, so it's valid only after `load()` completes.
    var hasBundles: Bool {
        let codes = FirebaseService.shared.bundleCodes
        return lineItems.contains { codes.contains($0.productCode) }
    }

    /// True when pressing "Paid" should open StockMovementScreen first (bundle invoices with no movement yet).
    var needsBundleMovement: Bool {
        canManageStock && hasBundles && !stockMovementCreated
    }

    /// True when the manual "Issue Stock" button should be shown.
    var canCreateMovementManually: Bool {
        canManageStock && !stockMovementCreated
    }

    // MARK: - Stock item lookup

    func stockItem(for cenikCode: String) -> FlexiBeeStockWithPrice? {
        FlexiBeeService.shared.stockWithPrices[id: cenikCode]
    }

    // MARK: - Edit Form Lifecycle

    func openEdit() {
        editFormVM = InvoiceFormViewModel(
            editingInvoice: invoice,
            fetchFirms: { [weak self] in
                guard let self else { return [] }
                await self.salesViewModel.loadFirms()
                return self.salesViewModel.firms
            },
            reloadFirms: { [weak self] in
                guard let self else { return [] }
                await self.salesViewModel.reloadFirms()
                return self.salesViewModel.firms
            },
            onSubmit: { [weak self] updatedInvoice in
                guard let self else { return }
                try await self.salesViewModel.updateInvoice(id: self.invoice.id, invoice: updatedInvoice)
            },
            onDeleteClient: { [weak self] id in
                guard let self else { return }
                try await self.salesViewModel.deleteClient(id: id)
            }
        )
        showEdit = true
    }

    func closeEdit() {
        let wasSuccessful = editFormVM?.didSucceed == true
        editFormVM = nil
        showEdit = false
        if wasSuccessful {
            Task { await reloadAfterEdit() }
        }
    }

    private func reloadAfterEdit() async {
        if let updated = try? await FlexiBeeService.shared.fetchSingleInvoice(id: invoice.id) {
            invoice = updated
        }
        await load()
    }

    // MARK: - Load

    func load() async {
        isLoadingItems = true
        loadError = nil
        do {
            lineItems = try await FlexiBeeService.shared
                .fetchLineItemsForInvoice(invoice.id)
                .filter { !$0.productName.isEmpty && $0.quantity > 0 }
        } catch {
            loadError = error.localizedDescription
        }
        // Movement fetch is non-fatal — a failure just means no section is shown
        if let (header, movItems) = try? await FlexiBeeService.shared
            .fetchStockMovement(for: invoice.invoiceNumber) {
            stockMovement = header
            stockMovementItems = movItems
            setStockMovementDone()
        }
        cashReceiptId = try? await FlexiBeeService.shared.fetchCashReceiptId(for: invoice.invoiceNumber)
        isLoadingItems = false
        if pendingPayWhenLoaded {
            pendingPayWhenLoaded = false
            selectPendingStatus(.paid)
        }
    }

    // MARK: - PDF

    func sharePDF(path: String, filename: String) async {
        isLoadingPDF = true
        defer { isLoadingPDF = false }
        do {
            let data = try await FlexiBeeService.shared.fetchPDF(path: path)
            pdfShareItem = PDFShareItem(data: data, filename: filename)
        } catch { }
    }

    func shareInvoicePDF() async {
        let filename = "\(invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
        await sharePDF(path: "/faktura-vydana/\(invoice.id).pdf", filename: filename)
    }

    func shareCashReceiptPDF() async {
        guard let rid = cashReceiptId else { return }
        let filename = "receipt-\(invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
        await sharePDF(path: "/pokladni-pohyb/\(rid).pdf", filename: filename)
    }

    func shareBothPDFs() async {
        guard let rid = cashReceiptId else { await shareInvoicePDF(); return }
        isLoadingPDF = true
        defer { isLoadingPDF = false }
        do {
            let invoiceName = "\(invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
            let receiptName = "receipt-\(invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
            async let invoiceData = FlexiBeeService.shared.fetchPDF(path: "/faktura-vydana/\(invoice.id).pdf")
            async let receiptData = FlexiBeeService.shared.fetchPDF(path: "/pokladni-pohyb/\(rid).pdf")
            let (inv, rec) = try await (invoiceData, receiptData)
            pdfShareItem = PDFShareItem(files: [(inv, invoiceName), (rec, receiptName)])
        } catch { }
    }

    // MARK: - Stock Movement

    private func setStockMovementDone() {
        stockMovementCreated = true
    }

    /// Creates a stock movement for all non-bundle line items.
    /// Called automatically when confirming payment on a non-bundle invoice.
    private func autoCreateStockMovement() async {
        let bundleCodes = FirebaseService.shared.bundleCodes
        let lines: [NewStockMovementLine] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty, !bundleCodes.contains(item.productCode) else { return nil }
            return NewStockMovementLine(productCode: "code:\(item.productCode)", quantity: item.quantity)
        }
        guard !lines.isEmpty else { setStockMovementDone(); return }

        let movement = NewStockMovement(
            description: "Vydej k \(invoice.invoiceNumber)",
            lines: lines
        )
        do {
            try await FlexiBeeService.shared.createStockMovement(movement)
            setStockMovementDone()
            await FlexiBeeService.shared.forceSync()
        } catch {
            openStockMovement()
        }
    }

    /// Parses bundle component lines from invoice finalText (zavTxt).
    /// Expected line format: `- CODE: Product name` — lines without a code are skipped (e.g. gifts).
    private func parseBundleComponents(from text: String?) -> [StockMovementItemDraft] {
        guard let text, !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            let content = String(trimmed.dropFirst(2))
            guard let colonRange = content.range(of: ": ") else { return nil }
            let code = String(content[content.startIndex..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let name = String(content[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty, !code.contains(" ") else { return nil }
            return StockMovementItemDraft(productCode: code, productName: name, quantity: 1)
        }
    }

    func manualCreateMovement() {
        openStockMovement(markAsPaidAfter: false)
    }

    func openStockMovement(markAsPaidAfter: Bool = true) {
        let bundleCodes = FirebaseService.shared.bundleCodes

        let regularDrafts: [InvoiceLineItemDraft] = lineItems.compactMap { item in
            guard !item.productCode.isEmpty, !bundleCodes.contains(item.productCode) else { return nil }
            var draft = InvoiceLineItemDraft()
            draft.name = item.productName
            draft.productCode = item.productCode
            draft.quantity = String(format: "%g", item.quantity)
            return draft
        }

        let parsedComponents = parseBundleComponents(from: invoice.finalText)

        let bundleSections: [BundleSection] = lineItems.compactMap { item in
            guard bundleCodes.contains(item.productCode) else { return nil }
            return BundleSection(bundleName: item.productName, bundleCode: item.productCode, components: parsedComponents)
        }

        pendingMovement = PendingMovement(
            invoiceId: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            items: regularDrafts,
            bundleSections: bundleSections,
            onMovementCreated: { [weak self] in
                self?.setStockMovementDone()
                if markAsPaidAfter {
                    await self?.setPaymentStatus(.paid)
                }
            }
        )
        showStockMovement = true
    }

    func editStockMovement() {
        guard let movement = stockMovement else { return }
        let oldMovementId = movement.id
        let editDrafts: [InvoiceLineItemDraft] = stockMovementItems.compactMap { item in
            guard item.isValid else { return nil }
            var draft = InvoiceLineItemDraft()
            draft.name = item.productName
            draft.productCode = item.productCode
            draft.quantity = String(format: "%g", item.quantityIssued)
            return draft
        }
        pendingMovement = PendingMovement(
            invoiceId: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            items: editDrafts,
            onMovementCreated: { [weak self] in
                try? await FlexiBeeService.shared.deleteStockMovementById(oldMovementId)
                await self?.load()
            }
        )
        showStockMovement = true
    }

    // MARK: - Payment status

    func selectPendingStatus(_ status: PaymentStatus) {
        if status == .paid, isLoadingItems {
            pendingPayWhenLoaded = true
            return
        }
        if status == .paid {
            showPaymentMethodPicker = true
            return
        }
        pendingStatus = status
        showStatusAlert = true
    }

    func selectPaymentMethod(_ method: PaymentMethod) {
        pendingPaymentMethod = method
        if needsBundleMovement {
            openStockMovement(markAsPaidAfter: true)
        } else {
            pendingStatus = .paid
            showStatusAlert = true
        }
    }

    func confirmStatusChange() {
        guard let s = pendingStatus else { return }
        pendingStatus = nil
        let task = Task { await self.setPaymentStatus(s) }
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
        let method = pendingPaymentMethod ?? .prevod
        pendingPaymentMethod = nil
        do {
            if status == .paid, method == .hotove {
                try await FlexiBeeService.shared.createCashReceipt(for: invoice)
            }
            try await FlexiBeeService.shared.updateInvoicePaymentStatus(id: invoice.id, status: status, method: method)
            do {
                if let updated = try await FlexiBeeService.shared.fetchSingleInvoice(id: invoice.id) {
                    invoice = updated
                }
            } catch { }
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
            try await FlexiBeeService.shared.deleteStockMovement(for: invoice.invoiceNumber)
            try await salesViewModel.deleteInvoice(id: invoice.id)
            router.pop()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
        isDeleting = false
    }
}
