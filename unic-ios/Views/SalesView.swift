import SwiftUI
import Charts
import IdentifiedCollections

// MARK: - Analytics Tab

struct AnalyticsTabView: View {
    @ObservedObject var viewModel: SalesViewModel
    @State private var router = AppRouter()

    var body: some View {
        AppNavigationStack(router: router, salesViewModel: viewModel) {
            AnalyticsSectionView(viewModel: viewModel, router: router)
                .navigationTitle(String.sales_analytics)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SyncButton(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate) {
                            Task { await viewModel.forceSync() }
                        }
                    }
                }
                .overlay {
                    if viewModel.isLoading && viewModel.invoices.isEmpty { LoadingOverlay() }
                }
                .task { await viewModel.loadIfNeeded() }
        }
    }
}

// MARK: - Invoices Tab

struct InvoicesTabView: View {
    @ObservedObject var viewModel: SalesViewModel
    @State private var router = AppRouter()
    @State private var showCreateInvoice = false

    var body: some View {
        AppNavigationStack(router: router, salesViewModel: viewModel) {
            InvoicesSectionView(viewModel: viewModel)
                .navigationTitle(String.sales_invoices)
                .toolbar {
                    if AuthService.shared.canCreateInvoice {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showCreateInvoice = true } label: {
                                Image(systemName: "square.and.pencil").fontWeight(.semibold)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SyncButton(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate) {
                            Task { await viewModel.forceSync() }
                        }
                    }
                }
                .overlay {
                    if viewModel.isLoading && viewModel.invoices.isEmpty { LoadingOverlay() }
                }
                .task { await viewModel.loadIfNeeded() }
                .sheet(isPresented: $showCreateInvoice) {
                    InvoiceFormSheetView(salesViewModel: viewModel)
                }
        }
    }
}

// MARK: - Analytics Content

private struct AnalyticsSectionView: View {
    @ObservedObject var viewModel: SalesViewModel
    var router: AppRouter

    private let pageSize = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $viewModel.period) {
                    ForEach(SalesPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: czk(viewModel.totalRevenue),  label: String.sales_kpi_revenue, icon: "banknote",              color: .blue)
                    StatCard(value: czk(viewModel.paidRevenue),   label: String.sales_kpi_paid,    icon: "checkmark.circle.fill", color: .green)
                    StatCard(value: czk(viewModel.unpaidRevenue), label: String.sales_kpi_unpaid,  icon: "clock",                 color: .orange)
                    StatCard(
                        value: "\(viewModel.overdueCount)",
                        label: String.sales_kpi_overdue,
                        icon: "exclamationmark.circle.fill",
                        color: viewModel.overdueCount > 0 ? .red : .secondary
                    )
                }
                .padding(.horizontal, 16)

                if !viewModel.monthlyRevenue.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("sales_chart_monthly_revenue")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                        Chart(viewModel.monthlyRevenue) { item in
                            BarMark(
                                x: .value("sales_chart_month", item.label),
                                y: .value("sales_chart_revenue", item.revenue)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 200)
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                }

                let clients = viewModel.topClients
                if !clients.isEmpty {
                    RankingSection(
                        title: String.sales_top_clients,
                        seeAllDestination: clients.count > pageSize ? .allTopClients : nil
                    ) {
                        ForEach(Array(clients.prefix(pageSize).enumerated()), id: \.offset) { idx, client in
                            RankingRow(rank: idx + 1, title: client.name, subtitle: nil,
                                       value: czk(client.revenue), subvalue: nil,
                                       isLast: idx == min(clients.count, pageSize) - 1)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                let products = viewModel.productAnalytics
                if !products.isEmpty {
                    RankingSection(
                        title: String.sales_top_products,
                        seeAllDestination: products.count > pageSize ? .allTopProducts : nil
                    ) {
                        ForEach(Array(products.prefix(pageSize).enumerated()), id: \.offset) { idx, p in
                            let stockItem = FlexiBeeService.shared.stockWithPrices[id: p.code]
                            let row = RankingRow(
                                rank: idx + 1,
                                title: p.name,
                                subtitle: p.code,
                                value: czk(p.revenue),
                                subvalue: String.sales_quantity(Int(p.quantity)),
                                isLast: idx == min(products.count, pageSize) - 1
                            )
                            if let stockItem {
                                Button { router.push(.product(stockItem)) } label: {
                                    row.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                row
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Invoices Content

private struct InvoicesSectionView: View {
    @ObservedObject var viewModel: SalesViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SalesFilterChip(title: String.filter_all, isSelected: viewModel.statusFilter == nil) {
                        viewModel.statusFilter = nil
                    }
                    ForEach(PaymentStatus.allCases, id: \.self) { status in
                        SalesFilterChip(title: status.label, isSelected: viewModel.statusFilter == status, color: status.color) {
                            viewModel.statusFilter = viewModel.statusFilter == status ? nil : status
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            List {
                ForEach(viewModel.filteredInvoices) { invoice in
                    NavigationLink(value: AppDestination.invoice(invoice)) {
                        InvoiceRowContent(invoice: invoice)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $viewModel.searchText, prompt: String.sales_search_prompt)
            .overlay {
                if viewModel.filteredInvoices.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(String.sales_invoices_empty, systemImage: "doc.text")
                }
            }
        }
    }
}

// MARK: - Invoice Row

private struct InvoiceRowContent: View {
    let invoice: FlexiBeeInvoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invoice.invoiceNumber).font(.callout.bold())
                Spacer()
                InvoiceStatusBadge(status: invoice.paymentStatus)
            }
            Text(invoice.clientName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                if let date = invoice.issueDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(czk(invoice.total)).font(.subheadline.bold())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - All Top Products

struct AllTopProductsView: View {
    @ObservedObject var viewModel: SalesViewModel
    var router: AppRouter

    var body: some View {
        List {
            ForEach(Array(viewModel.filteredTopProducts.enumerated()), id: \.offset) { idx, p in
                let stockItem = FlexiBeeService.shared.stockWithPrices[id: p.code]
                if let stockItem {
                    Button { router.push(.product(stockItem)) } label: {
                        StockWithPriceRow(item: stockItem).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    RankingRow(rank: idx + 1, title: p.name, subtitle: p.code,
                               value: czk(p.revenue), subvalue: String.sales_quantity(Int(p.quantity)),
                               isLast: true)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchTextTopProducts, prompt: String.sales_search_prompt)
        .navigationTitle(String.sales_top_products)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.filteredTopProducts.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "shippingbox")
            }
        }
    }
}

// MARK: - All Top Clients

struct AllTopClientsView: View {
    @ObservedObject var viewModel: SalesViewModel

    var body: some View {
        List {
            ForEach(Array(viewModel.filteredTopClients.enumerated()), id: \.offset) { idx, client in
                RankingRow(rank: idx + 1, title: client.name, subtitle: nil,
                           value: czk(client.revenue), subvalue: nil, isLast: true)
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchTextTopClients, prompt: String.sales_search_prompt)
        .navigationTitle(String.sales_top_clients)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.filteredTopClients.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "person.2")
            }
        }
    }
}

// MARK: - Ranking Section

private struct RankingSection<Content: View>: View {
    let title: String
    var seeAllDestination: AppDestination? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let dest = seeAllDestination {
                    NavigationLink(value: dest) {
                        Text(String.see_all).font(.caption).foregroundStyle(Color.accentColor)
                    }
                }
            }
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RankingRow: View {
    let rank: Int
    let title: String
    let subtitle: String?
    let value: String
    let subvalue: String?
    let isLast: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout).lineLimit(2)
                    if let sub = subtitle {
                        Text(sub).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(value).font(.callout.bold())
                    if let sub = subvalue {
                        Text(sub).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !isLast { Divider() }
        }
    }
}

// MARK: - Status Badge

struct InvoiceStatusBadge: View {
    let status: PaymentStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Filter Chip

private struct SalesFilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
