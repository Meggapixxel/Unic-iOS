// FILE: unic-ios/Features/Sales/SalesView.swift
import Charts
import ComposableArchitecture
import SwiftUI

// MARK: - Sales View

struct SalesView: View {
    @Bindable var store: StoreOf<SalesFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            salesRoot
                .navigationTitle(String.sales_nav_title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { salesToolbar }
                .task { store.send(.onLoad) }
        } destination: { pathStore in
            switch pathStore.case {
            case let .invoice(detailStore):
                InvoiceDetailView(store: detailStore)
            case let .allTopProducts(productsStore):
                AllTopProductsView(store: productsStore)
            case let .allTopClients(clientsStore):
                AllTopClientsView(store: clientsStore)
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.createInvoice,
                action: \.destination.createInvoice
            )
        ) { _ in
            // Bridge to existing InvoiceFormScreen MVVM until it is ported to TCA
            Text("Create Invoice")
                .padding()
        }
    }

    // MARK: - Root body

    @ViewBuilder
    private var salesRoot: some View {
        switch store.section {
        case .analytics:
            AnalyticsSection(store: store)
        case .invoices:
            InvoicesSection(store: store)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var salesToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("", selection: Binding(
                get: { store.section },
                set: { store.send(.sectionChanged($0)) }
            )) {
                ForEach(SalesSection.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        ToolbarItem(placement: .topBarTrailing) {
            SyncDateLabel(isLoading: store.isLoading, lastSyncDate: store.lastSyncDate)
        }
    }
}

// MARK: - Analytics Section

private struct AnalyticsSection: View {
    let store: StoreOf<SalesFeature>
    private let pageSize = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Period picker
                Picker("", selection: Binding(
                    get: { store.period },
                    set: { store.send(.periodChanged($0)) }
                )) {
                    ForEach(SalesPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Period navigator
                HStack(spacing: 20) {
                    Button { store.send(.goToPrevPeriod) } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Text(store.periodLabel)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 140)
                    Button { store.send(.goToNextPeriod) } label: {
                        Image(systemName: "chevron.right").fontWeight(.semibold)
                    }
                    .disabled(!store.canGoNext)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                if store.hasPeriodData {
                    // KPI cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        KPICard(value: czk(store.totalRevenue),  label: String.sales_kpi_revenue, icon: "banknote",              color: .blue)
                        KPICard(value: czk(store.paidRevenue),   label: String.sales_kpi_paid,    icon: "checkmark.circle.fill", color: .green)
                        KPICard(value: czk(store.unpaidRevenue), label: String.sales_kpi_unpaid,  icon: "clock",                 color: .orange)
                        KPICard(
                            value: "\(store.overdueCount)",
                            label: String.sales_kpi_overdue,
                            icon: "exclamationmark.circle.fill",
                            color: store.overdueCount > 0 ? .red : .secondary
                        )
                    }
                    .padding(.horizontal, 16)

                    // Monthly chart
                    if !store.monthlyRevenue.isEmpty {
                        MonthlyRevenueChart(points: store.monthlyRevenue)
                    }

                    // Top clients
                    let clients = store.topClients.prefix(5)
                    if !clients.isEmpty {
                        SalesRankingSection(
                            title: String.sales_top_clients,
                            seeAllLabel: store.topClients.count > 5 ? String.see_all : nil,
                            seeAllAction: {
                                store.send(.path(.push(
                                    id: store.path.ids.max().map { $0 + 1 } ?? 0,
                                    state: .allTopClients(AllTopClientsFeature.State(
                                        clients: Array(store.topClients)
                                    ))
                                )))
                            }
                        ) {
                            ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                                SalesRankingRow(
                                    rank: idx + 1,
                                    title: client.name,
                                    subtitle: nil,
                                    value: czk(client.revenue),
                                    isLast: idx == clients.count - 1
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Top products (placeholder — needs movement data from dependency)
                    // When movement data is wired in, replace with real data
                    if store.topClients.count > 0 {
                        // Products section placeholder - populated when movement items are available
                        EmptyView()
                    }
                } else {
                    ContentUnavailableView(String.no_data, systemImage: "chart.bar")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { store.send(.forceSync) }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Invoices Section

private struct InvoicesSection: View {
    @Bindable var store: StoreOf<SalesFeature>

    var body: some View {
        List {
            // Status filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SalesFilterChip(
                        title: String.filter_all,
                        isSelected: store.statusFilter == nil
                    ) {
                        store.send(.statusFilterChanged(nil))
                    }
                    ForEach(PaymentStatus.allCases, id: \.self) { status in
                        SalesFilterChip(
                            title: status.label,
                            isSelected: store.statusFilter == status,
                            color: status.color
                        ) {
                            store.send(.statusFilterChanged(store.statusFilter == status ? nil : status))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets())

            // Invoice list
            ForEach(store.filteredInvoices) { invoice in
                Button {
                    store.send(.invoiceTapped(invoice))
                } label: {
                    InvoiceRowView(invoice: invoice)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .searchable(text: $store.searchText, prompt: String.sales_search_prompt)
        .refreshable { store.send(.forceSync) }
        .overlay {
            if store.filteredInvoices.isEmpty && !store.isLoading {
                ContentUnavailableView(String.sales_invoices_empty, systemImage: "doc.text")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button { store.send(.createInvoiceTapped) } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Invoice Row View

struct InvoiceRowView: View {
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

// MARK: - KPI Card

struct KPICard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Monthly Revenue Chart

private struct MonthlyRevenueChart: View {
    let points: [MonthlyRevenuePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String.sales_chart_monthly_revenue)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
            Chart(points) { item in
                BarMark(
                    x: .value(String.sales_chart_month, item.label),
                    y: .value(String.sales_chart_revenue, item.revenue)
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
}

// MARK: - Ranking Section

private struct SalesRankingSection<Content: View>: View {
    let title: String
    var seeAllLabel: String?
    var seeAllAction: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let label = seeAllLabel {
                    Button(action: { seeAllAction?() }) {
                        Text(label).font(.caption).foregroundStyle(Color.accentColor)
                    }
                }
            }
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SalesRankingRow: View {
    let rank: Int
    let title: String
    let subtitle: String?
    let value: String
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
                Text(value).font(.callout.bold())
            }
            if !isLast { Divider() }
        }
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

// MARK: - All Top Products View

struct AllTopProductsView: View {
    @Bindable var store: StoreOf<AllTopProductsFeature>

    var body: some View {
        List {
            ForEach(Array(store.filtered.enumerated()), id: \.offset) { idx, p in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.callout).lineLimit(2)
                        Text(p.code).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String.sales_quantity(Int(p.quantity))).font(.callout.bold())
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .searchable(text: $store.searchText, prompt: String.sales_search_prompt)
        .navigationTitle(String.sales_top_products)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.filtered.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "shippingbox")
            }
        }
    }
}

// MARK: - All Top Clients View

struct AllTopClientsView: View {
    @Bindable var store: StoreOf<AllTopClientsFeature>

    var body: some View {
        List {
            ForEach(Array(store.filtered.enumerated()), id: \.offset) { idx, client in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(client.name).font(.callout).lineLimit(2)
                    Spacer()
                    Text(czk(client.revenue)).font(.callout.bold())
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .searchable(text: $store.searchText, prompt: String.sales_search_prompt)
        .navigationTitle(String.sales_top_clients)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.filtered.isEmpty {
                ContentUnavailableView(String.no_data, systemImage: "person.2")
            }
        }
    }
}
