import SwiftUI
import Charts

// MARK: - Analytics Tab

struct AnalyticsTabView: View {
    @ObservedObject var viewModel: SalesViewModel

    var body: some View {
        NavigationStack {
            AnalyticsSectionView(viewModel: viewModel)
                .navigationTitle(String.sales_analytics)
                .toolbar { syncToolbar }
                .overlay {
                    if viewModel.isLoading && viewModel.invoices.isEmpty { loadingOverlay }
                }
                .task { await viewModel.loadIfNeeded() }
        }
    }

    @ToolbarContentBuilder
    private var syncToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { syncButton }
    }

    private var syncButton: some View {
        Button { Task { await viewModel.forceSync() } } label: {
            if viewModel.isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(viewModel.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String.never)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(viewModel.lastSyncDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
            }
        }
        .disabled(viewModel.isLoading)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("loading").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Invoices Tab

struct InvoicesTabView: View {
    @ObservedObject var viewModel: SalesViewModel
    @State private var showCreateInvoice = false

    var body: some View {
        NavigationStack {
            InvoicesSectionView(viewModel: viewModel)
                .navigationTitle(String.sales_invoices)
                .toolbar { invoicesToolbar }
                .overlay {
                    if viewModel.isLoading && viewModel.invoices.isEmpty { loadingOverlay }
                }
                .task { await viewModel.loadIfNeeded() }
                .sheet(isPresented: $showCreateInvoice) {
                    InvoiceFormSheetView(salesViewModel: viewModel)
                }
                .navigationDestination(for: FlexiBeeInvoice.self) { invoice in
                    InvoiceDetailView(
                        invoice: invoice,
                        salesViewModel: viewModel,
                        isAdmin: AuthService.shared.isAdmin
                    )
                }
                .navigationDestination(for: FlexiBeeStockWithPrice.self) { product in
                    FlexiBeeProductDetailView(item: product)
                }
        }
    }

    @ToolbarContentBuilder
    private var invoicesToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showCreateInvoice = true } label: {
                Image(systemName: "square.and.pencil").fontWeight(.semibold)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { syncButton }
    }

    private var syncButton: some View {
        Button { Task { await viewModel.forceSync() } } label: {
            if viewModel.isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(viewModel.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String.never)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(viewModel.lastSyncDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
            }
        }
        .disabled(viewModel.isLoading)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("loading").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Analytics Content

private struct AnalyticsSectionView: View {
    @ObservedObject var viewModel: SalesViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $viewModel.period) {
                    ForEach(SalesPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    KPICard(value: czk(viewModel.totalRevenue),  label: String.sales_kpi_revenue, icon: "banknote",                 color: .blue)
                    KPICard(value: czk(viewModel.paidRevenue),   label: String.sales_kpi_paid,    icon: "checkmark.circle.fill",    color: .green)
                    KPICard(value: czk(viewModel.unpaidRevenue), label: String.sales_kpi_unpaid,  icon: "clock",                    color: .orange)
                    KPICard(
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

                if !viewModel.topClients.isEmpty {
                    RankingSection(title: String.sales_top_clients) {
                        ForEach(Array(viewModel.topClients.enumerated()), id: \.offset) { idx, client in
                            RankingRow(rank: idx + 1, title: client.name, subtitle: nil,
                                       value: czk(client.revenue), subvalue: nil,
                                       isLast: idx == viewModel.topClients.count - 1)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !viewModel.productAnalytics.isEmpty {
                    RankingSection(title: String.sales_top_products) {
                        ForEach(Array(viewModel.productAnalytics.prefix(10).enumerated()), id: \.offset) { idx, p in
                            let stockItem = FlexiBeeService.shared.stockWithPrices.first { $0.code == p.code }
                            let row = RankingRow(
                                rank: idx + 1,
                                title: p.name,
                                subtitle: p.code,
                                value: czk(p.revenue),
                                subvalue: String.sales_quantity(Int(p.quantity)),
                                isLast: idx == min(viewModel.productAnalytics.count, 10) - 1
                            )
                            if let stockItem {
                                NavigationLink { FlexiBeeProductDetailView(item: stockItem) } label: { row }
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
                    InvoiceRow(invoice: invoice)
                }
            }
            .listStyle(.plain)
            .searchable(text: $viewModel.searchText, prompt: "sales_search_prompt")
            .overlay {
                if viewModel.filteredInvoices.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(String.sales_invoices_empty, systemImage: "doc.text")
                }
            }
        }
    }
}

// MARK: - Invoice Row

private struct InvoiceRow: View {
    let invoice: FlexiBeeInvoice

    var body: some View {
        NavigationLink(value: invoice) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(invoice.invoiceNumber)
                        .font(.callout.bold())
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(czk(invoice.total))
                        .font(.subheadline.bold())
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Ranking Section

private struct RankingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
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

// MARK: - KPI Card

private struct KPICard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Helpers

private func czk(_ amount: Double) -> String {
    guard amount > 0 else { return "—" }
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "CZK"
    fmt.maximumFractionDigits = 0
    return fmt.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) Kč"
}
