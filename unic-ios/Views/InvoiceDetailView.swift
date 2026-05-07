import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View

struct InvoiceDetailView: View {
    @StateObject private var viewModel: InvoiceDetailViewModel

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel, router: AppRouter) {
        _viewModel = StateObject(wrappedValue: InvoiceDetailViewModel(
            invoice: invoice,
            salesViewModel: salesViewModel,
            router: router
        ))
    }

    var body: some View {
        List {
            headerSection
            infoSection
            notesSection
            primaryActionSection
            itemsSection
            stockMovementSection
            documentsSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.invoice.invoiceNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isUpdatingStatus {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(String.edit_invoice_action) { viewModel.showEdit = true }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showEdit) {
            InvoiceFormSheetView(salesViewModel: viewModel.salesViewModel, editingInvoice: viewModel.invoice)
        }
        .confirmationDialog(
            String.payment_method,
            isPresented: $viewModel.showPaymentMethodPicker,
            titleVisibility: .visible
        ) {
            Button(PaymentMethod.prevod.displayName) { viewModel.selectPaymentMethod(.prevod) }
            Button(PaymentMethod.hotove.displayName) { viewModel.selectPaymentMethod(.hotove) }
            Button(String.cancel, role: .cancel) { }
        }
        .sheet(isPresented: $viewModel.showStockMovement) {
            if let pending = viewModel.pendingMovement {
                StockMovementView(pending: pending)
            }
        }
        .alert(String.invoice_status_change_title, isPresented: $viewModel.showStatusAlert) {
            Button(viewModel.pendingStatus?.label ?? "") {
                viewModel.confirmStatusChange()
            }
            Button(String.cancel, role: .cancel) { viewModel.cancelStatusChange() }
        } message: {
            Text(String.invoice_status_change_to(viewModel.pendingStatus?.label ?? ""))
        }
        .alert(String.error, isPresented: $viewModel.showStatusError) {
            Button("OK") { }
        } message: {
            Text(viewModel.statusUpdateError ?? "")
        }
        .alert(String.delete_invoice_confirm_title, isPresented: $viewModel.showDeleteAlert) {
            Button(String.delete, role: .destructive) {
                Task { await viewModel.delete() }
            }
            Button(String.cancel, role: .cancel) { }
        } message: {
            Text(String.delete_invoice_confirm_body(viewModel.invoice.invoiceNumber))
        }
        .alert(String.error, isPresented: $viewModel.showDeleteError) {
            Button("OK") { }
        } message: {
            Text(viewModel.deleteError ?? "")
        }
        .sheet(item: $viewModel.pdfShareURL) { url in
            ShareSheet(url: url)
        }
        .task {
            await viewModel.load()
            await FlexiBeeService.shared.loadIfNeeded()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.invoice.invoiceNumber)
                        .font(.title3.bold())
                    Text(viewModel.invoice.clientName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(czk(viewModel.invoice.total))
                        .font(.title3.bold())
                    HStack(spacing: 4) {
                        if let method = viewModel.invoice.paymentMethod {
                            Image(systemName: method.icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        InvoiceStatusBadge(status: viewModel.invoice.paymentStatus)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section(String.create_invoice_dates) {
            if let date = viewModel.invoice.issueDate {
                LabeledContent(String.create_invoice_issue_date) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let date = viewModel.invoice.dueDate {
                LabeledContent(String.create_invoice_due_date) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(viewModel.invoice.paymentStatus == .overdue ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        if let notes = viewModel.invoice.notes, !notes.isEmpty {
            Section(String.create_invoice_notes) {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Items

    private var itemsSection: some View {
        Section {
            if viewModel.isLoadingItems {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let err = viewModel.loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if viewModel.lineItems.isEmpty {
                Text(String.invoice_detail_no_items)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(viewModel.lineItems) { item in
                    let stockItem = viewModel.stockItem(for: item.cenikCode)
                    Group {
                        if let stockItem {
                            NavigationLink(value: AppDestination.product(stockItem)) {
                                lineItemRow(item)
                            }
                        } else {
                            lineItemRow(item)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(String.invoice_detail_items)
                Spacer()
                if !viewModel.isLoadingItems, !viewModel.lineItems.isEmpty {
                    Text(czk(viewModel.lineItems.reduce(0) { $0 + $1.total }))
                        .font(.caption.bold())
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Line Item Row

    private func lineItemRow(_ item: FlexiBeeInvoiceItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.callout)
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
            Text(czk(item.total))
                .font(.callout.bold())
        }
        .padding(.vertical, 2)
    }

    // MARK: - Stock Movement

    @ViewBuilder
    private var stockMovementSection: some View {
        if !viewModel.stockMovementItems.isEmpty {
            Section {
                ForEach(viewModel.stockMovementItems) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.productName)
                                .font(.callout)
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
            } header: {
                HStack {
                    Text(String.stock_movement_title)
                    Spacer()
                    if viewModel.canEditStockMovement {
                        Button(String.stock_movement_edit) {
                            viewModel.editStockMovement()
                        }
                        .font(.caption.bold())
                        .textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        if !viewModel.isLoadingItems, viewModel.canDelete {
            Section {
                Button {
                    viewModel.showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isDeleting {
                            ProgressView()
                        } else {
                            Text(String.delete_invoice_action)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.white)
                .listRowBackground(Color.red)
                .disabled(viewModel.isDeleting)
            }
        }
    }

    // MARK: - Documents

    @ViewBuilder
    private var documentsSection: some View {
        Section {
            Button {
                Task { await viewModel.shareInvoicePDF() }
            } label: {
                HStack {
                    Label(String.pdf_invoice, systemImage: "doc.fill")
                    Spacer()
                    if viewModel.isLoadingPDF {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(viewModel.isLoadingPDF)

            if viewModel.cashReceiptId != nil {
                Button {
                    Task { await viewModel.shareCashReceiptPDF() }
                } label: {
                    Label(String.pdf_cash_receipt, systemImage: "doc.text.fill")
                }
                .disabled(viewModel.isLoadingPDF)
            }
        } header: {
            Text(String.pdf_documents)
        }
    }

    // MARK: - Primary Action

    @ViewBuilder
    private var primaryActionSection: some View {
        let showPaid = !viewModel.isLoadingItems
            && viewModel.invoice.paymentStatus != .paid
            && (viewModel.stockMovementCreated || viewModel.canManageStock)
        if showPaid {
            Section {
                if viewModel.canCreateMovementManually {
                    Button {
                        viewModel.manualCreateMovement()
                    } label: {
                        HStack {
                            Spacer()
                            Label(String.stock_movement_create, systemImage: "shippingbox.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .foregroundStyle(.white)
                    .listRowBackground(Color.blue)
                    .disabled(viewModel.isUpdatingStatus)
                }

                Button {
                    viewModel.selectPendingStatus(.paid)
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isUpdatingStatus {
                            ProgressView()
                        } else {
                            Label(String.payment_paid, systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.white)
                .listRowBackground(Color.green)
                .disabled(viewModel.isUpdatingStatus)
            }
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
