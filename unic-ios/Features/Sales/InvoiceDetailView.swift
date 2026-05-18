// FILE: unic-ios/Features/Sales/InvoiceDetailView.swift
import ComposableArchitecture
import SwiftUI

// MARK: - Invoice Detail View

/// Full-screen detail view for a single FlexiBee invoice, driven by `InvoiceDetailFeature`.
/// Displays a progress timeline, header, dates, notes, line items, and a stock-movement section,
/// with bottom-bar actions for deletion, accounting, payment, and PDF sharing.
struct InvoiceDetailView: View {
    @Bindable var store: StoreOf<InvoiceDetailFeature>
    /// Whether the line-items disclosure group is expanded.
    @State private var itemsExpanded = false
    /// Whether the stock-movement disclosure group is expanded.
    @State private var stockExpanded = false

    var body: some View {
        List {
            timelineSection
            headerSection
            infoSection
            notesSection
            itemsSection
            stockMovementSection
        }
        .listStyle(.insetGrouped)
        .navigationInlineTitle(store.invoice.invoiceNumber)
        .toolbar {
            if store.canEdit && !store.isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        store.send(.editTapped)
                    }
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

    // MARK: - Timeline Section

    private var timelineSection: some View {
        Section {
            InvoiceTimeline(
                isAccounted: store.isAccounted,
                stockMovementCreated: store.stockMovementCreated,
                isPaid: store.invoice.paymentStatus == .paid
            )
        }
        .listRowBackground(Color.clear)
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
                    Text((store.invoice.total).czk)
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

            HStack(spacing: 12) {
                // Заúčtování — active (text+icon) until done, then hidden
                if !store.isAccounted {
                    Button { store.send(.accountingTapped) } label: {
                        Label(String.invoice_stage_registered, systemImage: "checkmark.seal")
                    }
                }

                // Vydej — icon only until accounting done, then text+icon, hidden when created
                if !store.stockMovementCreated {
                    Button { store.send(.openStockMovement) } label: {
                        if store.isAccounted {
                            Label(String.stock_movement_create, systemImage: "shippingbox")
                        } else {
                            Image(systemName: "shippingbox")
                        }
                    }
                }

                // Оплата — icon only until vydej done, then text+icon, hidden when paid
                if store.invoice.paymentStatus != .paid {
                    Button { store.send(.setPaymentStatus(.paid, nil)) } label: {
                        if store.isAccounted && store.stockMovementCreated {
                            Label(String.invoice_stage_paid, systemImage: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .tint(.green)
                }

                // Documents — visible only after payment
                if store.invoice.paymentStatus == .paid {
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
                        Text((store.lineItems.reduce(0) { $0 + $1.total }).czk)
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
                Text((item.total).czk).font(.callout.bold())
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
                        Button("Edit") {
                            store.send(.openStockMovement)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

}

// MARK: - PDF Share Sheet View

/// Wraps `UIActivityViewController` to present the PDF share sheet from SwiftUI.
private struct PDFShareSheetView: UIViewControllerRepresentable {
    /// The PDF data to share, potentially containing multiple files.
    let item: PDFShareItem

    /// - Returns: A `UIActivityViewController` pre-loaded with the PDF temp-file URLs.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: item.tempURLs, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Payment Method Picker View

/// Bottom sheet that lets the user pick the payment method before confirming a status change.
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

/// A single row in the payment-method picker sheet.
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

// MARK: - Invoice Timeline

/// `PreferenceKey` used to propagate the computed scale factor from child to parent in `InvoiceTimeline`.
private struct _TimelineScaleKey: PreferenceKey {
    static var defaultValue: CGFloat { 1 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

/// Horizontal step-indicator that animates each stage of the invoice lifecycle.
private struct InvoiceTimeline: View {
    let isAccounted: Bool
    let stockMovementCreated: Bool
    let isPaid: Bool

    @State private var scale: CGFloat = 1

    var body: some View {
        steps
            .scaleEffect(scale, anchor: .center)
            .overlay(
                GeometryReader { available in
                    steps
                        .fixedSize()
                        .hidden()
                        .background(GeometryReader { natural in
                            Color.clear.preference(
                                key: _TimelineScaleKey.self,
                                value: min(1, available.size.width / max(natural.size.width, 1))
                            )
                        })
                }
            )
            .padding(.vertical, 6)
            .onPreferenceChange(_TimelineScaleKey.self) { newScale in
                withAnimation(.easeOut(duration: 0.2)) { scale = newScale }
            }
    }

    private var steps: some View {
        HStack(spacing: 0) {
            InvoiceTimelineStep(icon: "doc.text.fill",          label: String.invoice_stage_created,    done: true,               delay: 0.0)
            InvoiceTimelineConnector(done: isAccounted,                                                                            delay: 0.15)
            InvoiceTimelineStep(icon: "checkmark.seal.fill",   label: String.invoice_stage_registered, done: isAccounted,         delay: 0.2)
            InvoiceTimelineConnector(done: stockMovementCreated,                                                                   delay: 0.35)
            InvoiceTimelineStep(icon: "shippingbox.fill",      label: String.invoice_stage_moved,      done: stockMovementCreated, delay: 0.4)
            InvoiceTimelineConnector(done: isPaid,                                                                                 delay: 0.55)
            InvoiceTimelineStep(icon: "checkmark.circle.fill", label: String.invoice_stage_paid,       done: isPaid,              delay: 0.6)
        }
    }
}

// MARK: - Stock Movement Bridge View

/// Bridges the TCA `StockMovementPlaceholderFeature` store to the MVVM `StockMovementScreen`,
/// converting TCA state into a `PendingMovement` and forwarding the outcome back as TCA actions.
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
