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
            itemsSection
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
                    if viewModel.canEdit {
                        statusMenuButton
                    } else {
                        InvoiceStatusBadge(status: viewModel.invoice.paymentStatus)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusMenuButton: some View {
        Menu {
            ForEach(
                PaymentStatus.allCases.filter { $0 != .overdue && $0 != viewModel.invoice.paymentStatus },
                id: \.self
            ) { status in
                Button {
                    viewModel.selectPendingStatus(status)
                } label: {
                    Label(status.label, systemImage: statusIcon(for: status))
                }
            }
        } label: {
            HStack(spacing: 3) {
                InvoiceStatusBadge(status: viewModel.invoice.paymentStatus)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(viewModel.isUpdatingStatus)
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

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        if viewModel.canDelete {
            Section {
                Button(role: .destructive) {
                    viewModel.showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isDeleting {
                            ProgressView()
                        } else {
                            Text(String.delete_invoice_action)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isDeleting)
            }
        }
    }

    // MARK: - Helpers

    private func statusIcon(for status: PaymentStatus) -> String {
        switch status {
        case .paid:    return "checkmark.circle.fill"
        case .partial: return "clock.badge.checkmark"
        case .unpaid:  return "clock"
        case .overdue: return "exclamationmark.circle.fill"
        }
    }
}
