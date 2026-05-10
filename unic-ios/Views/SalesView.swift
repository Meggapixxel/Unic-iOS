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
                        SyncDateLabel(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate)
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

    var body: some View {
        AppNavigationStack(router: router, salesViewModel: viewModel) {
            InvoicesSectionView(viewModel: viewModel)
                .navigationTitle(String.sales_invoices)
                .toolbar {
                    if AuthService.shared.canCreateInvoice {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { viewModel.openCreateInvoice() } label: {
                                Image(systemName: "square.and.pencil").fontWeight(.semibold)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SyncDateLabel(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate)
                    }
                }
                .overlay {
                    if viewModel.isLoading && viewModel.invoices.isEmpty { LoadingOverlay() }
                }
                .task { await viewModel.loadIfNeeded() }
                .sheet(
                    isPresented: Binding(
                        get: { viewModel.invoiceFormVM != nil },
                        set: { if !$0 { viewModel.closeCreateInvoice() } }
                    ),
                    onDismiss: {
                        if let id = viewModel.recentlyCreatedInvoiceId {
                            viewModel.clearRecentlyCreatedInvoice()
                            if let invoice = viewModel.invoices.first(where: { $0.id == id }) {
                                router.push(.invoice(invoice))
                            }
                        }
                    }
                ) {
                    if let formVM = viewModel.invoiceFormVM {
                        InvoiceFormView(viewModel: formVM, onDismiss: { viewModel.closeCreateInvoice() })
                    }
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
                if !products.isEmpty || !viewModel.allTimeProductSales.isEmpty {
                    TopProductsCard(viewModel: viewModel, router: router, pageSize: pageSize)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.forceSync() }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Invoices Content

private struct InvoicesSectionView: View {
    @ObservedObject var viewModel: SalesViewModel

    var body: some View {
        List {
            ForEach(viewModel.filteredInvoices) { invoice in
                NavigationLink(value: AppDestination.invoice(invoice)) {
                    InvoiceRowContent(invoice: invoice)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refreshInvoices() }
        .searchable(text: $viewModel.searchText, prompt: String.sales_search_prompt)
        .overlay {
            if viewModel.filteredInvoices.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(String.sales_invoices_empty, systemImage: "doc.text")
            }
        }
        .safeAreaInset(edge: .bottom) {
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
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .padding()
            .glassBackgroundRectangle(cornerRadius: 20)
            .padding()
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
                if let method = invoice.paymentMethod {
                    Image(systemName: method.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                        StockWithPriceRow(item: stockItem)
                            .id("\(stockItem.code)-\(stockItem.quantity)")
                            .contentShape(Rectangle())
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

private struct RankingSection<Content: View, Accessory: View>: View {
    let title: String
    var accessory: Accessory
    var seeAllDestination: AppDestination? = nil
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder picker: () -> Accessory = { EmptyView() },
        seeAllDestination: AppDestination? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = picker()
        self.seeAllDestination = seeAllDestination
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                accessory
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

// MARK: - Top Products Card (analytics inline)

private struct TopProductsCard: View {
    @ObservedObject var viewModel: SalesViewModel
    var router: AppRouter
    let pageSize: Int

    private var products: [ProductSales] {
        viewModel.topSalesMode == .allTime
            ? viewModel.allTimeProductSales
            : viewModel.productAnalytics
    }

    var body: some View {
        RankingSection(
            title: String.sales_top_products,
            picker: {
                Picker("", selection: $viewModel.topSalesMode) {
                    ForEach(TopSalesMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            },
            seeAllDestination: products.count > pageSize ? .topSales : nil
        ) {
            ForEach(Array(products.prefix(pageSize).enumerated()), id: \.offset) { idx, p in
                let stockItem = FlexiBeeService.shared.stockWithPrices[id: p.code]
                let row = RankingRow(
                    rank: idx + 1, title: p.name, subtitle: p.code,
                    value: czk(p.revenue),
                    subvalue: String.sales_quantity(Int(p.quantity)),
                    isLast: idx == min(products.count, pageSize) - 1
                )
                if let stockItem {
                    Button { router.push(.product(stockItem)) } label: { row.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

// MARK: - Top Sales View (dedicated screen)

struct TopSalesView: View {
    @ObservedObject var viewModel: SalesViewModel
    var router: AppRouter

    var body: some View {
        Group {
            if viewModel.topSalesMode == .allTime {
                allTimeList
            } else {
                byMonthList
            }
        }
        .navigationTitle(String.top_sales_title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $viewModel.topSalesMode) {
                    ForEach(TopSalesMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    private var allTimeList: some View {
        List {
            ForEach(Array(viewModel.filteredAllTimeTopProducts.enumerated()), id: \.offset) { idx, p in
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
        .overlay {
            if viewModel.filteredAllTimeTopProducts.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "shippingbox")
            }
        }
    }

    private var byMonthList: some View {
        List {
            ForEach(viewModel.productSalesByMonth) { month in
                Section {
                    ForEach(Array(month.products.prefix(10).enumerated()), id: \.offset) { idx, p in
                        let stockItem = FlexiBeeService.shared.stockWithPrices[id: p.code]
                        let row = RankingRow(
                            rank: idx + 1, title: p.name, subtitle: p.code,
                            value: czk(p.revenue), subvalue: String.sales_quantity(Int(p.quantity)),
                            isLast: idx == min(month.products.count, 10) - 1
                        )
                        if let stockItem {
                            Button { router.push(.product(stockItem)) } label: { row.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                } header: {
                    HStack {
                        Text(month.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(String.top_sales_month_total) \(czk(month.totalRevenue))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.productSalesByMonth.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "shippingbox")
            }
        }
    }
}
