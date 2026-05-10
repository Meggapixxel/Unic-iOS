import SwiftUI
import Charts
import IdentifiedCollections

// MARK: - Sales Tab (Analytics + Invoices combined)

enum SalesSection: String, CaseIterable {
    case analytics
    case invoices

    var label: String {
        switch self {
        case .analytics: return String.sales_analytics
        case .invoices:  return String.sales_invoices
        }
    }
}

struct SalesTabView: View {
    @ObservedObject var viewModel: SalesViewModel
    @State private var router = AppRouter()
    @State private var section: SalesSection = .invoices

    var body: some View {
        AppNavigationStack(router: router, salesViewModel: viewModel) {
            Group {
                switch section {
                case .analytics:
                    AnalyticsSectionView(viewModel: viewModel, router: router)
                case .invoices:
                    InvoicesSectionView(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $section) {
                        ForEach(SalesSection.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if section == .invoices, AuthService.shared.canCreateInvoice {
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

                HStack(spacing: 20) {
                    Button { viewModel.goToPrevPeriod() } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Text(viewModel.periodLabel)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 140)
                    Button { viewModel.goToNextPeriod() } label: {
                        Image(systemName: "chevron.right").fontWeight(.semibold)
                    }
                    .disabled(!viewModel.canGoNext)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                if viewModel.hasPeriodData {
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

                let clients = viewModel.topClients.prefix(5)
                if !clients.isEmpty {
                    RankingSection(title: String.sales_top_clients, seeAllDestination: nil) {
                        ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                            RankingRow(rank: idx + 1, title: client.name, subtitle: nil,
                                       value: czk(client.revenue), subvalue: nil,
                                       isLast: idx == clients.count - 1)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !viewModel.productAnalytics.isEmpty {
                    TopProductsCard(viewModel: viewModel, router: router, pageSize: pageSize)
                        .padding(.horizontal, 16)
                }
                } else {
                    ContentUnavailableView(String.no_data, systemImage: "chart.bar")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
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
        .safeAreaInset(edge: .top, spacing: 0) {
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
            .background(.bar)
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
                let row = RankingRow(rank: idx + 1, title: p.name, subtitle: p.code,
                                    value: String.sales_quantity(Int(p.quantity)), subvalue: nil,
                                    isLast: true)
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

    var body: some View {
        RankingSection(
            title: String.sales_top_products,
            seeAllDestination: viewModel.productAnalytics.count > pageSize ? .allTopProducts : nil
        ) {
            ForEach(Array(viewModel.productAnalytics.prefix(pageSize).enumerated()), id: \.offset) { idx, p in
                let stockItem = FlexiBeeService.shared.stockWithPrices[id: p.code]
                let row = RankingRow(
                    rank: idx + 1, title: p.name, subtitle: p.code,
                    value: String.sales_quantity(Int(p.quantity)),
                    subvalue: nil,
                    isLast: idx == min(viewModel.productAnalytics.count, pageSize) - 1
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

