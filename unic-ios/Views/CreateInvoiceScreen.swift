import SwiftUI
import Combine

// MARK: - Draft Model

/// Mutable draft for a single invoice line item, used in the create/edit invoice form.
struct InvoiceLineItemDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    /// FlexiBee product code; `nil` for "other" / free-text items.
    var productCode: String? = nil
    var quantity: String = "1"
    var unitPrice: String = ""
    /// When `true` the item is a free-text entry with no product code and a fixed quantity of 1.
    var isOther: Bool = false

    /// Quantity parsed from the user-editable string, accepting both `.` and `,` as decimal separators.
    var quantityDouble: Double { Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    /// Unit price parsed from the user-editable string, accepting both `.` and `,` as decimal separators.
    var unitPriceDouble: Double { Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    /// `true` when the item has a name, a positive unit price, and (for stock items) a positive quantity.
    var isValid: Bool {
        !name.isEmpty && unitPriceDouble > 0 && (isOther || quantityDouble > 0)
    }
    /// Computed line total (quantity × unit price).
    var total: Double { quantityDouble * unitPriceDouble }

    /// Converts the draft to the API model, using quantity `1` for "other" items.
    func toNewLine() -> NewInvoiceLine {
        NewInvoiceLine(name: name, productCode: productCode, quantity: isOther ? 1 : quantityDouble, unitPrice: unitPriceDouble)
    }
}

// MARK: - Form View

/// Full-screen invoice creation/editing form driven by `InvoiceFormViewModel`.
/// Supports firm picking, date selection, line-item management (with barcode scanning), and notes.
struct InvoiceFormScreen: View {
    @ObservedObject var viewModel: InvoiceFormViewModel
    /// Called after a successful submit or when the user cancels, so the parent can dismiss the sheet.
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
        Form {
            clientSection
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
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                }
                .disabled(viewModel.isSubmitting)
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSubmitting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .sheet(isPresented: $viewModel.showFirmPicker) {
            FirmPickerView(viewModel: viewModel, isPresented: $viewModel.showFirmPicker)
        }
        .sheet(isPresented: $viewModel.showProductPicker) {
            ProductPickerForInvoiceView(priceList: viewModel.priceList, onSelect: { item in
                if let itemID = viewModel.productPickerForItemID,
                   let idx = viewModel.lineItems.firstIndex(where: { $0.id == itemID }) {
                    viewModel.lineItems[idx].name = item.displayName
                    viewModel.lineItems[idx].productCode = item.code
                    viewModel.lineItems[idx].unitPrice = item.unitPrice
                } else {
                    var draft = InvoiceLineItemDraft()
                    draft.name = item.displayName
                    draft.productCode = item.code
                    draft.unitPrice = item.unitPrice
                    viewModel.lineItems.append(draft)
                }
            }, isPresented: $viewModel.showProductPicker)
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
            if success { onDismiss() }
        }
        } // NavigationStack
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section(String.create_invoice_client) {
            Button {
                viewModel.showFirmPicker = true
            } label: {
                HStack {
                    Text(viewModel.selectedFirm?.displayName ?? String.create_invoice_client_placeholder)
                        .foregroundStyle(viewModel.selectedFirm == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                LineItemRow(item: $item)
            }
            .onDelete { viewModel.lineItems.remove(atOffsets: $0) }

            Menu {
                Button {
                    viewModel.productPickerForItemID = nil
                    viewModel.showProductPicker = true
                } label: {
                    Label(String.create_invoice_add_item_from_stock, systemImage: "shippingbox")
                }
                Button {
                    viewModel.showBarcodeScanner = true
                } label: {
                    Label(String.create_invoice_add_item_scan, systemImage: "barcode.viewfinder")
                }
                Button {
                    var draft = InvoiceLineItemDraft()
                    draft.isOther = true
                    viewModel.lineItems.append(draft)
                } label: {
                    Label(String.create_invoice_add_item_manual, systemImage: "pencil")
                }
            } label: {
                Label(String.create_invoice_add_item, systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(String.create_invoice_items)
                Spacer()
                if viewModel.grandTotal > 0 {
                    Text((viewModel.grandTotal).czk)
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

/// Editable row for a single invoice line item, with quantity steppers and a unit-price field.
private struct LineItemRow: View {
    @Binding var item: InvoiceLineItemDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if item.isOther {
                    TextField(String.create_invoice_item_name, text: $item.name)
                } else {
                    Text(item.name)
                    if let code = item.productCode {
                        Text(code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String.create_invoice_item_qty + ":")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            let val = item.quantityDouble
                            if val > 1 { item.quantity = String(format: "%g", val - 1) }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        TextField("1", text: $item.quantity)
                            .keyboardType(.decimalPad)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .frame(width: 44)
                        Button {
                            let val = item.quantityDouble
                            item.quantity = String(format: "%g", val + 1)
                        } label: {
                            Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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
                    Text((item.total).czk)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Firm Picker

/// Searchable list of FlexiBee firms for selecting a client on an invoice.
/// Supports inline deletion (admin only) and navigating to the "Create Client" form.
struct FirmPickerView: View {
    @ObservedObject var viewModel: InvoiceFormViewModel
    @Binding var isPresented: Bool
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
                                isPresented = false
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
                    Button { isPresented = false } label: { Image(systemName: "xmark") }
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
                CreateClientView(formViewModel: viewModel, isPresented: $showCreateClient)
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
                isPresented = false
            }
        }
    }
}

// MARK: - Create Client View

/// Modal form for creating a new FlexiBee client from within the invoice creation flow.
struct CreateClientView: View {
    @ObservedObject var formViewModel: InvoiceFormViewModel
    @StateObject private var clientVM = CreateClientViewModel()
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ClientFormFields(
                        name: $clientVM.name,
                        ic: $clientVM.ic,
                        dic: $clientVM.dic,
                        email: $clientVM.email,
                        phone: $clientVM.phone
                    )
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
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(clientVM.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if clientVM.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button {
                            Task { await clientVM.submit(using: formViewModel) }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!clientVM.isValid)
                    }
                }
            }
            .onChange(of: clientVM.didSucceed) { _, success in
                if success { isPresented = false }
            }
        }
    }
}

// MARK: - Product Picker

/// Searchable product picker that lets the user choose a FlexiBee price-list item for a line.
struct ProductPickerForInvoiceView: View {
    let priceList: [FlexiBeeCenikItem]
    /// Called when the user selects a product; the picker dismisses itself.
    let onSelect: (FlexiBeeCenikItem) -> Void
    @Binding var isPresented: Bool
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
                        isPresented = false
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
                                Text((item.sellPriceVAT).czk)
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
                    Button { isPresented = false } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

