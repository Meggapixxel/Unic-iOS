import Foundation
import SwiftUI
import Combine

enum SalesPeriod: String, CaseIterable {
    case week    = "week"
    case month   = "month"
    case year    = "year"
    case allTime = "allTime"

    var displayName: String {
        switch self {
        case .week:    return String.period_week
        case .month:   return String.period_month
        case .year:    return String.period_year
        case .allTime: return String.period_all_time
        }
    }

    var dateRange: (from: Date, to: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .week:
            return (cal.date(byAdding: .day, value: -7, to: now)!, now)
        case .month:
            return (cal.date(from: cal.dateComponents([.year, .month], from: now))!, now)
        case .year:
            return (cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!, now)
        case .allTime:
            return (.distantPast, now)
        }
    }
}

struct MonthlyRevenue: Identifiable {
    let id      = UUID()
    let label:    String
    let month:    Date
    let revenue:  Double
}

struct ProductSales: Identifiable {
    let id       = UUID()
    let code:     String
    let name:     String
    let quantity: Double
    let revenue:  Double
}

enum TopSalesMode: String, CaseIterable {
    case allTime = "allTime"
    case byMonth = "byMonth"

    var displayName: String {
        switch self {
        case .allTime: return String.top_sales_all_time
        case .byMonth: return String.top_sales_by_month
        }
    }
}

struct MonthlyProductSales: Identifiable {
    let id         = UUID()
    let label:      String
    let month:      Date
    let products:   [ProductSales]
    var totalRevenue: Double { products.reduce(0) { $0 + $1.revenue } }
}

/// Central ViewModel for the Sales tab.
///
/// Cache strategy: invoices, invoice items, and stock movement items are persisted to
/// UserDefaults (JSON) with a 1-hour TTL. On app launch `restoreFromDisk()` pre-fills the
/// UI immediately; `loadIfNeeded()` skips the network if the cache is still valid.
///
/// `productAnalytics` is derived from stock movement items (not invoice line items) because
/// Chariot Studio has `zdrojProSkl` disabled — invoices don't auto-deduct stock, so movement
/// records are the only reliable source of actual product outflows.
///
/// `recentlyCreatedInvoiceId` is set after `fetchData()` completes inside `createInvoice()`.
/// The invoices tab's sheet `onDismiss` reads this to navigate directly to the new invoice
/// detail and trigger the stock movement flow.
@MainActor
final class SalesViewModel: ObservableObject {
    @Published private(set) var firms: [FlexiBeeFirm] = []
    @Published private(set) var isFirmsLoading = false
    @Published var period: SalesPeriod = .year
    @Published var topSalesMode: TopSalesMode = .allTime
    @Published var searchText = ""
    @Published var searchTextTopProducts = ""
    @Published var searchTextTopClients = ""
    @Published var statusFilter: PaymentStatus? = nil
    @Published private(set) var recentlyCreatedInvoiceId: String?
    @Published private(set) var invoiceFormVM: InvoiceFormViewModel?
    @Published var error: String?

    private let service = FlexiBeeService.shared
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "MMM"
        return fmt
    }()
    private static let monthYearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "LLLL yyyy"
        return fmt
    }()
    private var cancellables = Set<AnyCancellable>()

    var invoices:           [FlexiBeeInvoice]           { service.invoices }
    var invoiceItems:       [FlexiBeeInvoiceItem]       { service.invoiceItems }
    var stockMovementItems: [FlexiBeeStockMovementItem] { service.salesMovementItems }
    var isLoading:          Bool                        { service.isLoading }
    var lastSyncDate:       Date?                       { service.lastSyncDate }

    init() {
        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Invoice Form Lifecycle

    func openCreateInvoice() {
        invoiceFormVM = InvoiceFormViewModel(
            fetchFirms: { [weak self] in
                guard let self else { return [] }
                await self.loadFirms()
                return self.firms
            },
            reloadFirms: { [weak self] in
                guard let self else { return [] }
                await self.reloadFirms()
                return self.firms
            },
            onSubmit: { [weak self] invoice in
                guard let self else { return }
                try await self.createInvoice(invoice)
            },
            onDeleteClient: { [weak self] id in
                guard let self else { return }
                try await self.deleteClient(id: id)
            }
        )
    }

    func closeCreateInvoice() {
        invoiceFormVM = nil
    }

    // MARK: - Load

    func loadIfNeeded() async {
        await service.loadIfNeeded()
    }

    func forceSync() async {
        await service.forceSync()
    }

    func refreshInvoices() async {
        if AuthService.shared.canViewAnalytics {
            await service.forceSync()
        } else {
            await service.fetchInvoicesOnly()
        }
    }

    func loadFirms() async {
        guard firms.isEmpty else { return }
        isFirmsLoading = true
        do {
            firms = try await service.fetchFirms()
        } catch {
            self.error = error.localizedDescription
        }
        isFirmsLoading = false
    }

    func reloadFirms() async {
        isFirmsLoading = true
        do {
            firms = try await service.fetchFirms()
        } catch {
            self.error = error.localizedDescription
        }
        isFirmsLoading = false
    }

    func deleteClient(id: String) async throws {
        try await service.deleteFirm(id: id)
        firms.removeAll { $0.id == id }
    }

    @discardableResult
    func createInvoice(_ invoice: NewInvoice) async throws -> String {
        let id = try await service.createInvoice(invoice)
        await service.refreshInvoicesData()
        recentlyCreatedInvoiceId = id
        return id
    }

    func clearRecentlyCreatedInvoice() {
        recentlyCreatedInvoiceId = nil
    }

    func updateInvoice(id: String, invoice: NewInvoice) async throws {
        try await service.updateInvoice(id: id, invoice: invoice)
        await service.refreshInvoicesData()
    }

    func deleteInvoice(id: String) async throws {
        try await service.deleteInvoice(id: id)
        await service.refreshInvoicesData()
    }

    // MARK: - Period-scoped

    var periodInvoices: [FlexiBeeInvoice] {
        let (from, to) = period.dateRange
        return invoices.filter {
            guard let d = $0.issueDate else { return false }
            return d >= from && d <= to
        }
    }

    var periodItems: [FlexiBeeInvoiceItem] {
        let (from, to) = period.dateRange
        return invoiceItems.filter {
            guard let d = $0.date else { return false }
            return d >= from && d <= to
        }
    }

    var periodMovements: [FlexiBeeStockMovementItem] {
        let (from, to) = period.dateRange
        return stockMovementItems.filter {
            guard let d = $0.date else { return false }
            return d >= from && d <= to
        }
    }

    // MARK: - Filtered (Invoices tab)

    var filteredInvoices: [FlexiBeeInvoice] {
        var result = invoices
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.invoiceNumber.lowercased().contains(q) ||
                $0.clientName.lowercased().contains(q)
            }
        }
        if let status = statusFilter {
            result = result.filter { $0.paymentStatus == status }
        }
        return result
    }

    // MARK: - KPIs

    var totalRevenue:  Double { periodInvoices.reduce(0) { $0 + $1.total } }
    var paidRevenue:   Double { periodInvoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total } }
    var unpaidRevenue: Double { periodInvoices.filter { $0.paymentStatus == .unpaid || $0.paymentStatus == .overdue }.reduce(0) { $0 + $1.total } }
    var overdueCount:  Int   { periodInvoices.filter { $0.paymentStatus == .overdue }.count }

    // MARK: - Monthly chart

    var monthlyRevenue: [MonthlyRevenue] {
        let cal = Calendar.current
        let (from, _) = period.dateRange
        let grouped = Dictionary(grouping: periodInvoices) { inv -> Date in
            guard let d = inv.issueDate else { return from }
            return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? from
        }
        return grouped
            .map { MonthlyRevenue(label: Self.monthFormatter.string(from: $0.key), month: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
            .sorted { $0.month < $1.month }
    }

    // MARK: - Top clients

    var topClients: [(name: String, revenue: Double)] {
        Dictionary(grouping: periodInvoices) { $0.clientName }
            .map { (name: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
            .sorted { $0.revenue > $1.revenue }
    }

    var filteredTopClients: [(name: String, revenue: Double)] {
        guard !searchTextTopClients.isEmpty else { return topClients }
        let q = searchTextTopClients.lowercased()
        return topClients.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Product analytics

    var productAnalytics: [ProductSales] {
        let grouped = Dictionary(grouping: periodMovements) { $0.cenikCode }
        return grouped
            .map { code, items in
                ProductSales(
                    code: code,
                    name: items.first?.productName ?? code,
                    quantity: items.reduce(0) { $0 + $1.quantityIssued },
                    revenue: items.reduce(0) { $0 + $1.total }
                )
            }
            .sorted { $0.quantity > $1.quantity }
    }

    var filteredTopProducts: [ProductSales] {
        guard !searchTextTopProducts.isEmpty else { return productAnalytics }
        let q = searchTextTopProducts.lowercased()
        return productAnalytics.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    // MARK: - All-time & monthly product sales

    var allTimeProductSales: [ProductSales] {
        let grouped = Dictionary(grouping: stockMovementItems) { $0.cenikCode }
        return grouped
            .map { code, items in
                ProductSales(
                    code: code,
                    name: items.first?.productName ?? code,
                    quantity: items.reduce(0) { $0 + $1.quantityIssued },
                    revenue: items.reduce(0) { $0 + $1.total }
                )
            }
            .sorted { $0.quantity > $1.quantity }
    }

    var filteredAllTimeTopProducts: [ProductSales] {
        guard !searchTextTopProducts.isEmpty else { return allTimeProductSales }
        let q = searchTextTopProducts.lowercased()
        return allTimeProductSales.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    var productSalesByMonth: [MonthlyProductSales] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: stockMovementItems) { item -> Date in
            guard let d = item.date else { return .distantPast }
            return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? .distantPast
        }
        return grouped
            .compactMap { month, items -> MonthlyProductSales? in
                guard month != .distantPast else { return nil }
                let products = Dictionary(grouping: items) { $0.cenikCode }
                    .map { code, items in
                        ProductSales(
                            code: code,
                            name: items.first?.productName ?? code,
                            quantity: items.reduce(0) { $0 + $1.quantityIssued },
                            revenue: items.reduce(0) { $0 + $1.total }
                        )
                    }
                    .sorted { $0.quantity > $1.quantity }
                return MonthlyProductSales(
                    label: Self.monthYearFormatter.string(from: month),
                    month: month,
                    products: products
                )
            }
            .sorted { $0.month > $1.month }
    }
}
