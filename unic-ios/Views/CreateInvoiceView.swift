import SwiftUI
import Combine

// MARK: - Draft Model

struct InvoiceLineItemDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var productCode: String? = nil
    var quantity: String = "1"
    var unitPrice: String = ""

    var quantityDouble: Double { Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var unitPriceDouble: Double { Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var isValid: Bool { !name.isEmpty && quantityDouble > 0 && unitPriceDouble > 0 }
    var total: Double { quantityDouble * unitPriceDouble }

    func toNewLine() -> NewInvoiceLine {
        NewInvoiceLine(name: name, quantity: quantityDouble, unitPrice: unitPriceDouble)
    }
}

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
            } else {
                try await salesViewModel.createInvoice(invoice)
                await createStockMovement(from: lineItems)
            }
            didSucceed = true
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }

    private func createStockMovement(from items: [InvoiceLineItemDraft]) async {
        let lines = items.compactMap { item -> NewStockMovementLine? in
            guard let code = item.productCode, !code.isEmpty, item.quantityDouble > 0 else { return nil }
            return NewStockMovementLine(productCode: "code:\(code)", quantity: item.quantityDouble)
        }
        guard !lines.isEmpty else { return }
        let movement = NewStockMovement(documentType: "code:VYDEJ", description: nil, lines: lines)
        try? await FlexiBeeService.shared.createStockMovement(movement)
    }
}

// MARK: - Sheet Wrapper

struct InvoiceFormSheetView: View {
    @StateObject private var formVM: InvoiceFormViewModel

    init(salesViewModel: SalesViewModel, editingInvoice: FlexiBeeInvoice? = nil) {
        _formVM = StateObject(wrappedValue: InvoiceFormViewModel(
            salesViewModel: salesViewModel,
            editingInvoice: editingInvoice
        ))
    }

    var body: some View {
        InvoiceFormView(viewModel: formVM)
    }
}

// MARK: - Form View

struct InvoiceFormView: View {
    @ObservedObject var viewModel: InvoiceFormViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFirmPicker = false
    @State private var showProductPicker = false
    @State private var productPickerForItemID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                clientSection
                paymentMethodSection
                datesSection
                lineItemsSection
                notesSection
                if let error = viewModel.submitError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { dismiss() }
                        .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(viewModel.submitLabel) {
                            Task { await viewModel.submit() }
                        }
                        .disabled(!viewModel.isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showFirmPicker) {
                FirmPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showProductPicker) {
                ProductPickerForInvoiceView(priceList: viewModel.priceList) { item in
                    guard let itemID = productPickerForItemID,
                          let idx = viewModel.lineItems.firstIndex(where: { $0.id == itemID }) else { return }
                    viewModel.lineItems[idx].name = item.displayName
                    viewModel.lineItems[idx].productCode = item.code
                    viewModel.lineItems[idx].unitPrice = item.sellPriceVAT > 0
                        ? String(format: "%.0f", item.sellPriceVAT) : ""
                }
            }
            .overlay {
                if viewModel.isLoadingItems || viewModel.isSearchingBarcode {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(viewModel.isSearchingBarcode ? String.barcode_searching : String.loading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fullScreenCover(isPresented: $viewModel.showBarcodeScanner) {
                BarcodeScannerScreen(
                    onScan: { barcode in
                        Task { await viewModel.handleScannedBarcode(barcode) }
                    },
                    onDismiss: { viewModel.showBarcodeScanner = false }
                )
            }
            .alert(String.barcode_title, isPresented: Binding(
                get: { viewModel.barcodeError != nil },
                set: { _ in }
            )) {
                Button("OK") { }
            } message: {
                Text(viewModel.barcodeError ?? "")
            }
            .task { await viewModel.prepare() }
            .onChange(of: viewModel.didSucceed) { _, success in
                if success { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section(String.create_invoice_client) {
            Button {
                showFirmPicker = true
            } label: {
                HStack {
                    Text(viewModel.selectedFirm?.displayName ?? String.create_invoice_client_placeholder)
                        .foregroundStyle(viewModel.selectedFirm == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var paymentMethodSection: some View {
        Section(String.payment_method) {
            Picker(String.payment_method, selection: $viewModel.paymentMethod) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Label(method.displayName, systemImage: method.icon).tag(method)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var datesSection: some View {
        Section(String.create_invoice_dates) {
            DatePicker(String.create_invoice_issue_date, selection: $viewModel.issueDate, displayedComponents: .date)
            DatePicker(String.create_invoice_due_date, selection: $viewModel.dueDate, displayedComponents: .date)
        }
    }

    private var lineItemsSection: some View {
        Section {
            ForEach($viewModel.lineItems) { $item in
                LineItemRow(item: $item) {
                    productPickerForItemID = item.id
                    showProductPicker = true
                }
            }
            .onDelete { viewModel.lineItems.remove(atOffsets: $0) }

            Menu {
                Button {
                    viewModel.lineItems.append(InvoiceLineItemDraft())
                } label: {
                    Label(String.create_invoice_add_item_manual, systemImage: "plus")
                }
                Button {
                    viewModel.showBarcodeScanner = true
                } label: {
                    Label(String.create_invoice_add_item_scan, systemImage: "barcode.viewfinder")
                }
            } label: {
                Label(String.create_invoice_add_item, systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(String.create_invoice_items)
                Spacer()
                if viewModel.grandTotal > 0 {
                    Text(czk(viewModel.grandTotal))
                        .font(.caption.bold())
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var notesSection: some View {
        Section(String.create_invoice_notes) {
            TextField(String.create_invoice_notes_placeholder, text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }
}

// MARK: - Line Item Row

private struct LineItemRow: View {
    @Binding var item: InvoiceLineItemDraft
    let onPickProduct: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(String.create_invoice_item_name, text: $item.name)
                Button(action: onPickProduct) {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(String.create_invoice_item_qty + ":")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("1", text: $item.quantity)
                            .keyboardType(.decimalPad)
                            .font(.subheadline)
                            .frame(width: 48)
                    }
                    HStack(spacing: 4) {
                        Text(String.create_invoice_item_price + ":")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $item.unitPrice)
                            .keyboardType(.decimalPad)
                            .font(.subheadline)
                            .frame(width: 72)
                        Text("Kč")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if item.total > 0 {
                    Text(czk(item.total))
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Firm Picker

struct FirmPickerView: View {
    @ObservedObject var viewModel: InvoiceFormViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateClient = false
    @State private var deleteError: String?

    private var filtered: [FlexiBeeFirm] {
        guard !viewModel.firmPickerSearch.isEmpty else { return viewModel.firms }
        let q = viewModel.firmPickerSearch.lowercased()
        return viewModel.firms.filter {
            $0.displayName.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isFirmsLoading && viewModel.firms.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { firm in
                            Button {
                                viewModel.selectedFirm = firm
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(firm.displayName).foregroundStyle(.primary)
                                        Text(firm.code).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.selectedFirm?.id == firm.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.canDeleteClient {
                                    Button(role: .destructive) {
                                        Task {
                                            do { try await viewModel.deleteClient(firm) }
                                            catch { deleteError = error.localizedDescription }
                                        }
                                    } label: {
                                        Label(String.delete, systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $viewModel.firmPickerSearch, prompt: String.create_invoice_client_search)
                }
            }
            .navigationTitle(String.create_invoice_client)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { dismiss() }
                }
                if viewModel.canCreateClient {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreateClient = true } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateClient) {
                CreateClientView(formViewModel: viewModel)
            }
            .alert(String.error, isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .onChange(of: viewModel.justCreatedClient) { _, _ in
                dismiss()
            }
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

// MARK: - Create Client View

struct CreateClientView: View {
    @ObservedObject var formViewModel: InvoiceFormViewModel
    @StateObject private var clientVM = CreateClientViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String.create_invoice_client) {
                    TextField(String.create_client_name_placeholder, text: $clientVM.name)
                        .autocorrectionDisabled()
                }
                Section("IČO / DIČ") {
                    LabeledContent("IČO") {
                        TextField("12345678", text: $clientVM.ic)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("DIČ") {
                        TextField("CZ12345678", text: $clientVM.dic)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }
                Section(String.section_contacts) {
                    LabeledContent("Email") {
                        TextField("info@company.cz", text: $clientVM.email)
                            .keyboardType(.emailAddress)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent(String.phone_label) {
                        TextField("+420 123 456 789", text: $clientVM.phone)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let err = clientVM.error {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle(String.new_client)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { dismiss() }
                        .disabled(clientVM.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if clientVM.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(String.save) {
                            Task { await clientVM.submit(using: formViewModel) }
                        }
                        .disabled(!clientVM.isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: clientVM.didSucceed) { _, success in
                if success { dismiss() }
            }
        }
    }
}

// MARK: - Product Picker

struct ProductPickerForInvoiceView: View {
    let priceList: [FlexiBeeCenikItem]
    let onSelect: (FlexiBeeCenikItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [FlexiBeeCenikItem] {
        guard !search.isEmpty else { return priceList }
        let q = search.lowercased()
        return priceList.filter {
            $0.displayName.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .foregroundStyle(.primary)
                                Text(item.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.sellPriceVAT > 0 {
                                Text(czk(item.sellPriceVAT))
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: String.search_stock)
            .navigationTitle(String.create_invoice_pick_product)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { dismiss() }
                }
            }
        }
    }
}

