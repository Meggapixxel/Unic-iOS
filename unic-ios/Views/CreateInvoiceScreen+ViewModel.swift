import SwiftUI
import Combine

// MARK: - Invoice Form ViewModel

/// Shared ViewModel for invoice creation and editing.
///
/// `prepare()` reuses data already cached by `SalesViewModel` (firms, price list) to avoid
/// redundant network calls. In edit mode it also fetches the existing line items from FlexiBee.
///
/// `submit()` delegates to `SalesViewModel.createInvoice()` / `updateInvoice()` and sets
/// `didSucceed = true` on completion. Navigation (post-create stock movement flow) is handled
/// by the parent view reacting to `SalesViewModel.recentlyCreatedInvoiceId`.
@MainActor
final class InvoiceFormViewModel: ObservableObject {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    @Published var selectedFirm: FlexiBeeFirm?
    @Published var issueDate = Date()
    /// Default due date is 14 days after issue.
    @Published var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @Published var paymentMethod: PaymentMethod = .prevod
    @Published var notes = ""
    @Published var lineItems: [InvoiceLineItemDraft] = []
    /// Live search text bound to the firm picker's search field.
    @Published var firmPickerSearch = ""

    @Published private(set) var firms: [FlexiBeeFirm] = []
    @Published private(set) var priceList: [FlexiBeeCenikItem] = []
    @Published private(set) var isFirmsLoading = false
    /// Whether existing line items are being fetched for an invoice being edited.
    @Published private(set) var isLoadingItems = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    /// Set to `true` after a successful create or update, signalling the parent view to dismiss.
    @Published private(set) var didSucceed = false
    /// The newly created client, set after `createClient` succeeds; observed by the firm picker to auto-close.
    @Published private(set) var justCreatedClient: FlexiBeeFirm?

    @Published var showBarcodeScanner = false
    @Published private(set) var isSearchingBarcode = false
    @Published private(set) var barcodeError: String?

    @Published var showFirmPicker = false
    @Published var showProductPicker = false
    /// The line-item `id` that triggered the product picker, used to patch the correct row on selection.
    @Published var productPickerForItemID: UUID?

    /// The invoice being edited, or `nil` when creating a new invoice.
    let editingInvoice: FlexiBeeInvoice?
    /// When set, the matching firm is pre-selected after firms are loaded.
    let preSelectClientCode: String?
    private var isPrepared = false

    private let fetchFirmsAction: () async -> [FlexiBeeFirm]
    private let reloadFirmsAction: () async -> [FlexiBeeFirm]
    private let submitAction: (NewInvoice) async throws -> Void
    private let deleteClientAction: (String) async throws -> Void

    /// Whether the form is editing an existing invoice (as opposed to creating a new one).
    var isEditing: Bool { editingInvoice != nil }
    var title: String { String.create_invoice_title }
    var submitLabel: String { isEditing ? String.save : String.create_invoice_submit }

    var canCreateClient: Bool { AuthService.shared.canCreateClient }
    var canDeleteClient: Bool { AuthService.shared.canDeleteClient }

    /// `true` when a client is selected and at least one line item is valid.
    var isValid: Bool {
        selectedFirm != nil && lineItems.contains { $0.isValid }
    }

    /// Sum of all valid line item totals.
    var grandTotal: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }

    init(
        editingInvoice: FlexiBeeInvoice? = nil,
        preSelectClientCode: String? = nil,
        fetchFirms: @escaping () async -> [FlexiBeeFirm],
        reloadFirms: @escaping () async -> [FlexiBeeFirm],
        onSubmit: @escaping (NewInvoice) async throws -> Void,
        onDeleteClient: @escaping (String) async throws -> Void
    ) {
        self.editingInvoice = editingInvoice
        self.preSelectClientCode = preSelectClientCode
        self.fetchFirmsAction = fetchFirms
        self.reloadFirmsAction = reloadFirms
        self.submitAction = onSubmit
        self.deleteClientAction = onDeleteClient

        if let invoice = editingInvoice {
            issueDate     = invoice.issueDate ?? Date()
            dueDate       = invoice.dueDate ?? Date()
            paymentMethod = invoice.paymentMethod ?? .prevod
            notes         = invoice.notes ?? ""
        }
    }

    /// Loads firms and the FlexiBee price list (idempotent — subsequent calls are no-ops).
    /// In edit mode also fetches the invoice's existing line items.
    func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        isFirmsLoading = true
        firms = await fetchFirmsAction()
        isFirmsLoading = false

        await FlexiBeeService.shared.loadIfNeeded()
        priceList = FlexiBeeService.shared.priceList

        if let invoice = editingInvoice {
            if let clientCode = invoice.clientCode {
                selectedFirm = firms.first { $0.code == clientCode }
            }
            await loadLineItems(for: invoice.id)
        } else if let code = preSelectClientCode {
            selectedFirm = firms.first { $0.code == code }
        }
    }


    private func loadLineItems(for invoiceId: String) async {
        isLoadingItems = true
        do {
            let items = try await FlexiBeeService.shared.fetchLineItemsForInvoice(invoiceId)
            let drafts: [InvoiceLineItemDraft] = items.compactMap { item in
                let name = item.productName
                guard !name.isEmpty, item.quantity > 0 else { return nil }
                var draft = InvoiceLineItemDraft()
                draft.name = name
                draft.productCode = item.productCode.nilIfEmpty
                draft.isOther = draft.productCode == nil
                draft.quantity = String(format: "%g", item.quantity)
                let unit = item.total / item.quantity
                draft.unitPrice = unit > 0 ? String(format: "%.0f", unit) : ""
                return draft
            }
            if !drafts.isEmpty { lineItems = drafts }
        } catch {
            submitError = error.localizedDescription
        }
        isLoadingItems = false
    }

    /// Barcode scan handler: looks up the barcode in Firestore to get the article code,
    /// then matches it against the FlexiBee price list. `normalizeKod` strips non-alphanumeric
    /// characters so that codes like "UC-001" and "UC001" resolve to the same product.
    func handleScannedBarcode(_ barcode: String) async {
        showBarcodeScanner = false
        barcodeError = nil
        isSearchingBarcode = true
        defer { isSearchingBarcode = false }

        do {
            guard let article = try await FirebaseService.shared.lookupBarcodeArticle(barcode) else {
                barcodeError = String.barcode_not_found(barcode)
                return
            }
            let normalized = normalizeKod(article)
            guard let product = priceList.first(where: { normalizeKod($0.code) == normalized }) else {
                barcodeError = String.barcode_not_found(article)
                return
            }
            var draft = InvoiceLineItemDraft()
            draft.name = product.displayName
            draft.productCode = product.code
            draft.quantity = "1"
            draft.unitPrice = product.unitPrice
            lineItems.append(draft)
        } catch {
            barcodeError = String.barcode_search_error(error.localizedDescription)
        }
    }

    private func normalizeKod(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression).uppercased()
    }

    /// Creates a new FlexiBee firm, reloads the firms list, and selects the new client.
    /// - Parameter firm: The new firm data to submit.
    /// - Throws: A FlexiBee API error if creation fails.
    func createClient(_ firm: NewFirm) async throws {
        let created = try await FlexiBeeService.shared.createFirm(firm)
        firms = await reloadFirmsAction()
        selectedFirm = created
        justCreatedClient = created
    }

    /// Deletes a FlexiBee firm and removes it from the local list.
    /// Clears `selectedFirm` if the deleted firm was selected.
    /// - Throws: A FlexiBee API error if deletion fails.
    func deleteClient(_ firm: FlexiBeeFirm) async throws {
        try await deleteClientAction(firm.id)
        firms.removeAll { $0.id == firm.id }
        if selectedFirm?.id == firm.id { selectedFirm = nil }
    }

    /// Builds a `NewInvoice` from the current form state and delegates to `submitAction`.
    /// Sets `didSucceed = true` on success or populates `submitError` on failure.
    func submit() async {
        guard let firm = selectedFirm, isValid else { return }
        isSubmitting = true
        submitError = nil

        let invoice = NewInvoice(
            documentType:  "code:FAKTURA",
            clientCode:    "code:\(firm.code)",
            issueDate:     Self.dateFormatter.string(from: issueDate),
            dueDate:       Self.dateFormatter.string(from: dueDate),
            notes:         notes.nilIfEmpty,
            paymentMethod: paymentMethod.rawValue,
            lineItems:     lineItems.filter { $0.isValid }.map { $0.toNewLine() }
        )

        do {
            try await submitAction(invoice)
            didSucceed = true
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Create Client ViewModel

/// ViewModel for the "Create Client" sheet within the invoice form flow.
@MainActor
final class CreateClientViewModel: ObservableObject {
    @Published var name = ""
    @Published var ic = ""
    @Published var dic = ""
    @Published var email = ""
    @Published var phone = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var error: String?
    @Published private(set) var didSucceed = false

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Validates and submits the new client via `formVM.createClient`, then sets `didSucceed = true`.
    /// - Parameter formVM: The parent invoice form view model that owns the firm list.
    func submit(using formVM: InvoiceFormViewModel) async {
        guard isValid else { return }
        isSubmitting = true
        error = nil
        do {
            let firm = NewFirm(
                name:  name.trimmingCharacters(in: .whitespaces),
                ic:    ic.nilIfEmpty,
                dic:   dic.nilIfEmpty,
                email: email.nilIfEmpty,
                phone: phone.nilIfEmpty
            )
            try await formVM.createClient(firm)
            didSucceed = true
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
