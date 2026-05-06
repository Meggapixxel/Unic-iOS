import SwiftUI
import Combine
import IdentifiedCollections

// MARK: - View Model

@MainActor
final class InvoiceDetailViewModel: ObservableObject {
    @Published private(set) var invoice: FlexiBeeInvoice
    @Published private(set) var lineItems: [FlexiBeeInvoiceItem] = []
    @Published private(set) var isLoadingItems = false
    @Published private(set) var loadError: String?
    @Published private(set) var isUpdatingStatus = false
    @Published private(set) var statusUpdateError: String?

    init(invoice: FlexiBeeInvoice) {
        self.invoice = invoice
    }

    func load() async {
        isLoadingItems = true
        loadError = nil
        do {
            let raw = try await FlexiBeeService.shared.fetchLineItemsForInvoice(invoice.id)
            lineItems = raw.filter { !$0.productName.isEmpty && $0.quantity > 0 }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingItems = false
    }

    var canEdit: Bool {
        AuthService.shared.canEditInvoice || invoice.paymentStatus != .paid
    }

    func setPaymentStatus(_ status: PaymentStatus, salesVM: SalesViewModel) async {
        isUpdatingStatus = true
        statusUpdateError = nil
        do {
            try await FlexiBeeService.shared.updateInvoicePaymentStatus(id: invoice.id, status: status)
            if let updated = try? await FlexiBeeService.shared.fetchSingleInvoice(id: invoice.id) {
                invoice = updated
            }
            Task { await salesVM.forceSync() }
        } catch {
            statusUpdateError = error.localizedDescription
        }
        isUpdatingStatus = false
    }
}

// MARK: - View

struct InvoiceDetailView: View {
    @StateObject private var viewModel: InvoiceDetailViewModel
    @ObservedObject private var flexiBeeService = FlexiBeeService.shared
    @State private var showEdit = false
    @State private var pendingStatus: PaymentStatus?
    @State private var showStatusAlert = false
    @State private var showStatusError = false

    private let salesViewModel: SalesViewModel

    init(invoice: FlexiBeeInvoice, salesViewModel: SalesViewModel) {
        _viewModel = StateObject(wrappedValue: InvoiceDetailViewModel(invoice: invoice))
        self.salesViewModel = salesViewModel
    }

    var body: some View {
        List {
            headerSection
            infoSection
            notesSection
            itemsSection
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
                        Button(String.edit_invoice_action) { showEdit = true }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            InvoiceFormSheetView(salesViewModel: salesViewModel, editingInvoice: viewModel.invoice)
        }
        .alert(String.invoice_status_change_title, isPresented: $showStatusAlert) {
            Button(pendingStatus?.label ?? "") {
                guard let s = pendingStatus else { return }
                pendingStatus = nil
                Task { await viewModel.setPaymentStatus(s, salesVM: salesViewModel) }
            }
            Button(String.cancel, role: .cancel) { pendingStatus = nil }
        } message: {
            Text(String.invoice_status_change_to(pendingStatus?.label ?? ""))
        }
        .alert(String.error, isPresented: $showStatusError) {
            Button("OK") { }
        } message: {
            Text(viewModel.statusUpdateError ?? "")
        }
        .onChange(of: viewModel.statusUpdateError) { _, err in
            if err != nil { showStatusError = true }
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
                    pendingStatus = status
                    showStatusAlert = true
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
                    let stockItem = flexiBeeService.stockWithPrices[id: item.cenikCode]
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
