// FILE: unic-ios/Features/Sales/InvoiceDetailView.swift
import ComposableArchitecture
import SwiftUI

// MARK: - Invoice Detail View

struct InvoiceDetailView: View {
    @Bindable var store: StoreOf<InvoiceDetailFeature>
    @State private var itemsExpanded = false
    @State private var stockExpanded = false

    var body: some View {
        List {
            headerSection
            infoSection
            notesSection
            itemsSection
            stockMovementSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(store.invoice.invoiceNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canEdit && !store.isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String.edit_invoice_action) {
                        store.send(.editTapped)
                    }
                    .fontWeight(.semibold)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                bottomBar
            }
        }
        .task { store.send(.onLoad) }
        // Edit form sheet
        .sheet(
            item: $store.scope(
                state: \.destination?.editForm,
                action: \.destination.editForm
            )
        ) { formStore in
            InvoiceFormBridgeView(store: formStore)
        }
        // Stock movement sheet
        .sheet(
            item: $store.scope(
                state: \.destination?.stockMovement,
                action: \.destination.stockMovement
            )
        ) { movStore in
            StockMovementBridgeView(store: movStore)
        }
        // Payment method picker — shown when destination is .statusChange
        .sheet(
            item: $store.scope(
                state: \.destination?.statusChange,
                action: \.destination.statusChange
            )
        ) { statusStore in
            PaymentMethodPickerView(store: statusStore)
                .presentationDetents([.fraction(0.35)])
        }
        // Delete confirmation alert
        .alert(
            String.delete_invoice_confirm_title,
            isPresented: Binding(
                get: {
                    if case .deleteAlert = store.destination { return true }
                    return false
                },
                set: { if !$0 { store.send(.destination(.dismiss)) } }
            )
        ) {
            Button(String.delete, role: .destructive) {
                store.send(.destination(.presented(.deleteAlert(.confirmed))))
            }
            Button(String.cancel, role: .cancel) {
                store.send(.destination(.presented(.deleteAlert(.cancelled))))
            }
        } message: {
            Text(String.delete_invoice_confirm_body(store.invoice.invoiceNumber))
        }
        // PDF share sheet
        .sheet(
            item: Binding(
                get: { store.pdfShareItem },
                set: { if $0 == nil { store.send(.pdfShareDismissed) } }
            )
        ) { item in
            PDFShareSheetView(item: item)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.invoice.invoiceNumber)
                        .font(.title3.bold())
                    Button {
                        store.send(.clientTapped)
                    } label: {
                        Text(store.invoice.clientName)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(czk(store.invoice.total))
                        .font(.title3.bold())
                    HStack(spacing: 4) {
                        if let method = store.invoice.paymentMethod {
                            Image(systemName: method.icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        InvoiceStatusBadge(status: store.invoice.paymentStatus)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section(String.create_invoice_dates) {
            if let date = store.invoice.issueDate {
                LabeledContent(String.create_invoice_issue_date) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let date = store.invoice.dueDate {
                LabeledContent(String.create_invoice_due_date) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(store.invoice.paymentStatus == .overdue ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private var notesSection: some View {
        if let notes = store.invoice.notes, !notes.isEmpty {
            Section(String.create_invoice_notes) {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if !store.isLoading {
            // Delete
            Button {
                store.send(.deleteTapped)
            } label: {
                Image(systemName: "trash")
            }
            .tint(.red)

            Spacer()

            HStack(spacing: 20) {
                // Stock movement
                if !store.stockMovementCreated {
                    Button {
                        store.send(.openStockMovement)
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    .disabled(store.invoice.paymentStatus == .paid)
                }

                // Payment status
                Button {
                    store.send(.setPaymentStatus(.paid, nil))
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .tint(store.invoice.paymentStatus == .paid ? .secondary : .green)
                .disabled(store.invoice.paymentStatus == .paid)

                // Documents / PDF
                Button {
                    let isCash = store.invoice.paymentMethod == .hotove && store.cashReceiptId != nil
                    if isCash {
                        store.send(.shareBothPDFs)
                    } else {
                        store.send(.shareInvoicePDF)
                    }
                } label: {
                    if store.isLoadingPDF {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.text.fill")
                    }
                }
                .disabled(store.isLoadingPDF)
            }
            .padding(.trailing, 8)
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $itemsExpanded) {
                if store.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if store.lineItems.isEmpty {
                    Text(String.invoice_detail_no_items)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(store.lineItems) { item in
                        lineItemRow(item)
                    }
                }
            } label: {
                HStack {
                    Text(String.invoice_detail_items)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    if !store.isLoading, !store.lineItems.isEmpty {
                        Text(czk(store.lineItems.reduce(0) { $0 + $1.total }))
                            .font(.caption.bold())
                    }
                }
            }
        }
    }

    private func lineItemRow(_ item: FlexiBeeInvoiceItem) -> some View {
        Button {
            if !item.productCode.isEmpty {
                store.send(.productTapped(item.productCode))
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.productName).font(.callout)
                    if !item.productCode.isEmpty {
                        Text(item.productCode)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(String.create_invoice_item_qty): \(String(format: "%g", item.quantity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(czk(item.total)).font(.callout.bold())
                if !item.productCode.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.productCode.isEmpty)
    }

    // MARK: - Stock Movement Section

    @ViewBuilder
    private var stockMovementSection: some View {
        if !store.stockMovementItems.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $stockExpanded) {
                    ForEach(store.stockMovementItems) { item in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.productName).font(.callout)
                                if !item.productCode.isEmpty {
                                    Text(item.productCode)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(String.create_invoice_item_qty): \(String(format: "%g", item.quantityIssued))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    HStack {
                        Text(String.stock_movement_title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        // Edit movement button
                        Button(String.stock_movement_edit) {
                            store.send(.openStockMovement)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .textCase(nil)
                    }
                }
            }
        }
    }

}

// MARK: - PDF Share Sheet View

private struct PDFShareSheetView: UIViewControllerRepresentable {
    let item: PDFShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: item.tempURLs, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Payment Method Picker View

private struct PaymentMethodPickerView: View {
    let store: StoreOf<StatusChangeFeature>

    var body: some View {
        VStack(spacing: 0) {
            Text(String.payment_method)
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider()
            ForEach(Array(PaymentMethod.allCases), id: \.self) { (method: PaymentMethod) in
                _PaymentMethodRow(
                    method: method,
                    isSelected: store.method == method,
                    onTap: { store.send(.confirmed(store.status, method)) }
                )
                Divider()
            }
            Button(role: .cancel) {
                store.send(.cancelled)
            } label: {
                Text(String.cancel)
            }
            .padding(.vertical, 14)
        }
    }
}

private struct _PaymentMethodRow: View {
    let method: PaymentMethod
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: method.icon)
                Text(method.displayName)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stock Movement Bridge View

private struct StockMovementBridgeView: View {
    let store: StoreOf<StockMovementPlaceholderFeature>

    @StateObject private var viewModel: StockMovementViewModel
    @State private var isPresented = true

    init(store: StoreOf<StockMovementPlaceholderFeature>) {
        self.store = store
        let draftItems: [InvoiceLineItemDraft] = store.lineItems.compactMap { item in
            guard let code = item.stockCode, item.quantity > 0 else { return nil }
            var draft = InvoiceLineItemDraft()
            draft.name = item.productName
            draft.productCode = code
            draft.quantity = String(format: "%g", item.quantity)
            return draft
        }
        let pending = PendingMovement(
            invoiceId: store.invoiceId,
            invoiceNumber: store.invoiceNumber,
            items: draftItems
        )
        _viewModel = StateObject(wrappedValue: StockMovementViewModel(pending: pending))
    }

    var body: some View {
        StockMovementScreen(viewModel: viewModel, isPresented: $isPresented)
            .onChange(of: isPresented) { _, presented in
                guard !presented else { return }
                if viewModel.submittedMovement {
                    store.send(.submitted)
                } else {
                    store.send(.skipped)
                }
            }
    }
}
