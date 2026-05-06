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
                viewModel.lineItems[idx].unitPrice = item.unitPrice
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
        } // NavigationStack
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

