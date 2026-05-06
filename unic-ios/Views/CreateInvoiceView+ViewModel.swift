import SwiftUI
import Combine

// MARK: - Invoice Form ViewModel

@MainActor
final class InvoiceFormViewModel: ObservableObject {
    @Published var selectedFirm: FlexiBeeFirm?
    @Published var issueDate = Date()
    @Published var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @Published var paymentMethod: PaymentMethod = .prevod
    @Published var notes = ""
    @Published var lineItems: [InvoiceLineItemDraft] = [InvoiceLineItemDraft()]
    @Published var firmPickerSearch = ""

    @Published private(set) var firms: [FlexiBeeFirm] = []
    @Published private(set) var priceList: [FlexiBeeCenikItem] = []
    @Published private(set) var isFirmsLoading = false
    @Published private(set) var isLoadingItems = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    @Published private(set) var didSucceed = false
    @Published private(set) var justCreatedClient: FlexiBeeFirm?

    @Published var showBarcodeScanner = false
    @Published private(set) var isSearchingBarcode = false
    @Published private(set) var barcodeError: String?

    let editingInvoice: FlexiBeeInvoice?
    private let salesViewModel: SalesViewModel

    var isEditing: Bool { editingInvoice != nil }
    var title: String { isEditing ? String.edit_invoice_title : String.create_invoice_title }
    var submitLabel: String { isEditing ? String.save : String.create_invoice_submit }

    var canCreateClient: Bool { AuthService.shared.canCreateClient }
    var canDeleteClient: Bool { AuthService.shared.canDeleteClient }

    var isValid: Bool {
        selectedFirm != nil && lineItems.contains { $0.isValid }
    }

    var grandTotal: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }

    init(salesViewModel: SalesViewModel, editingInvoice: FlexiBeeInvoice? = nil) {
        self.salesViewModel = salesViewModel
        self.editingInvoice = editingInvoice

        if let invoice = editingInvoice {
            issueDate     = invoice.issueDate ?? Date()
            dueDate       = invoice.dueDate ?? Date()
            paymentMethod = invoice.paymentMethod ?? .prevod
            notes         = invoice.notes ?? ""
        }
    }

    func prepare() async {
        // Load firms
        isFirmsLoading = true
        if salesViewModel.firms.isEmpty {
            await salesViewModel.loadFirms()
        }
        firms = salesViewModel.firms
        isFirmsLoading = false

        // Load price list
        await FlexiBeeService.shared.loadIfNeeded()
        priceList = FlexiBeeService.shared.priceList

        // Pre-fill for edit mode
        if let invoice = editingInvoice {
            if let clientCode = invoice.clientCode {
                selectedFirm = firms.first { $0.code == clientCode }
            }
            await loadLineItems(for: invoice.id)
        }
    }


    private func loadLineItems(for invoiceId: String) async {
        isLoadingItems = true
        if let items = try? await FlexiBeeService.shared.fetchLineItemsForInvoice(invoiceId) {
            let drafts: [InvoiceLineItemDraft] = items.compactMap { item in
                let name = item.productName
                guard !name.isEmpty, item.quantity > 0 else { return nil }
                var draft = InvoiceLineItemDraft()
                draft.name = name
                draft.productCode = item.productCode.isEmpty ? nil : item.productCode
                draft.quantity = String(format: "%g", item.quantity)
                let unit = item.total / item.quantity
                draft.unitPrice = unit > 0 ? String(format: "%.0f", unit) : ""
                return draft
            }
            if !drafts.isEmpty { lineItems = drafts }
        }
        isLoadingItems = false
    }

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
            draft.unitPrice = product.sellPriceVAT > 0 ? String(format: "%.0f", product.sellPriceVAT) : ""
            lineItems.append(draft)
        } catch {
            barcodeError = String.barcode_search_error(error.localizedDescription)
        }
    }

    private func normalizeKod(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression).uppercased()
    }

    func createClient(_ firm: NewFirm) async throws {
        let created = try await FlexiBeeService.shared.createFirm(firm)
        await salesViewModel.reloadFirms()
        firms = salesViewModel.firms
        selectedFirm = created
        justCreatedClient = created
    }

    func deleteClient(_ firm: FlexiBeeFirm) async throws {
        try await salesViewModel.deleteClient(id: firm.id)
        firms.removeAll { $0.id == firm.id }
        if selectedFirm?.id == firm.id { selectedFirm = nil }
    }

    func submit() async {
        guard let firm = selectedFirm, isValid else { return }
        isSubmitting = true
        submitError = nil

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        let invoice = NewInvoice(
            documentType:  "code:FAKTURA",
            clientCode:    "code:\(firm.code)",
            issueDate:     fmt.string(from: issueDate),
            dueDate:       fmt.string(from: dueDate),
            notes:         notes.isEmpty ? nil : notes,
            paymentMethod: paymentMethod.rawValue,
            lineItems:     lineItems.filter { $0.isValid }.map { $0.toNewLine() }
        )

        do {
            if let invoiceId = editingInvoice?.id {
                try await salesViewModel.updateInvoice(id: invoiceId, invoice: invoice)
                try await updateStockMovement(from: lineItems, for: invoiceId)
            } else {
                let newId = try await salesViewModel.createInvoice(invoice)
                try await createLinkedStockMovement(from: lineItems, for: newId)
            }
            didSucceed = true
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }

    // Creates a VYDEJ (outflow) stock movement. Description "inv:{invoiceId}" is the link key.
    // Only items picked from the price list (have a productCode) generate movement lines.
    private func createLinkedStockMovement(from items: [InvoiceLineItemDraft], for invoiceId: String) async throws {
        let lines = stockMovementLines(from: items)
        guard !lines.isEmpty else { return }
        let movement = NewStockMovement(
            documentType: "code:VYDEJ",
            description: "inv:\(invoiceId)",
            lines: lines
        )
        try await FlexiBeeService.shared.createStockMovement(movement)
    }

    // On invoice edit: deletes the old movement (found by popis), then creates a fresh one.
    // If no linked movement exists (e.g. invoice predates this feature), just creates a new one.
    private func updateStockMovement(from items: [InvoiceLineItemDraft], for invoiceId: String) async throws {
        if let oldId = try await FlexiBeeService.shared.fetchStockMovementId(linkedToInvoiceId: invoiceId) {
            try await FlexiBeeService.shared.deleteStockMovement(id: oldId)
        }
        try await createLinkedStockMovement(from: items, for: invoiceId)
    }

    // Only lines with a price-list code produce warehouse movement; manual name-only items are skipped.
    private func stockMovementLines(from items: [InvoiceLineItemDraft]) -> [NewStockMovementLine] {
        items.compactMap { item -> NewStockMovementLine? in
            guard let code = item.productCode, !code.isEmpty, item.quantityDouble > 0 else { return nil }
            return NewStockMovementLine(productCode: "code:\(code)", quantity: item.quantityDouble)
        }
    }
}

// MARK: - Create Client ViewModel

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

    func submit(using formVM: InvoiceFormViewModel) async {
        guard isValid else { return }
        isSubmitting = true
        error = nil
        do {
            let firm = NewFirm(
                name:  name.trimmingCharacters(in: .whitespaces),
                ic:    ic.isEmpty    ? nil : ic,
                dic:   dic.isEmpty   ? nil : dic,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone
            )
            try await formVM.createClient(firm)
            didSucceed = true
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
