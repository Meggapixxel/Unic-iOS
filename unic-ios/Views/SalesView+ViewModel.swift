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

@MainActor
final class SalesViewModel: ObservableObject {
    @Published private(set) var invoices: [FlexiBeeInvoice] = []
    @Published private(set) var invoiceItems: [FlexiBeeInvoiceItem] = []
    @Published private(set) var stockMovementItems: [FlexiBeeStockMovementItem] = []
    @Published private(set) var firms: [FlexiBeeFirm] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isFirmsLoading = false
    @Published private(set) var error: String?
    @Published private(set) var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "sales_lastSync") as? Date
    @Published var period: SalesPeriod = .year
    @Published var searchText = ""
    @Published var searchTextTopProducts = ""
    @Published var searchTextTopClients = ""
    @Published var statusFilter: PaymentStatus? = nil

    private let service = FlexiBeeService.shared
    private static let cacheTTL: TimeInterval = 60 * 60
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "MMM"
        return fmt
    }()
    private static let invoicesKey         = "sales_cache_invoices"
    private static let invoiceItemsKey     = "sales_cache_invoice_items"
    private static let stockMovementsKey   = "sales_cache_stock_movements"

    init() {
        restoreFromDisk()
    }

    // MARK: - Cache

    var isCacheValid: Bool {
        guard let last = lastSyncDate else { return false }
        return Date().timeIntervalSince(last) < Self.cacheTTL
    }

    private func restoreFromDisk() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: Self.invoicesKey),
           let saved = try? decoder.decode([FlexiBeeInvoice].self, from: data) {
            invoices = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.invoiceItemsKey),
           let saved = try? decoder.decode([FlexiBeeInvoiceItem].self, from: data) {
            invoiceItems = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.stockMovementsKey),
           let saved = try? decoder.decode([FlexiBeeStockMovementItem].self, from: data) {
            stockMovementItems = saved
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(invoices) {
            UserDefaults.standard.set(data, forKey: Self.invoicesKey)
        }
        if let data = try? encoder.encode(invoiceItems) {
            UserDefaults.standard.set(data, forKey: Self.invoiceItemsKey)
        }
        if let data = try? encoder.encode(stockMovementItems) {
            UserDefaults.standard.set(data, forKey: Self.stockMovementsKey)
        }
    }

    // MARK: - Load

    func loadIfNeeded() async {
        guard !isCacheValid else { return }
        await fetchData()
    }

    func forceSync() async {
        await fetchData()
    }

    func loadFirms() async {
        guard firms.isEmpty else { return }
        isFirmsLoading = true
        if let f = try? await service.fetchFirms() {
            firms = f
        }
        isFirmsLoading = false
    }

    func reloadFirms() async {
        isFirmsLoading = true
        if let f = try? await service.fetchFirms() {
            firms = f
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
        await fetchData()
        return id
    }

    func updateInvoice(id: String, invoice: NewInvoice) async throws {
        try await service.updateInvoice(id: id, invoice: invoice)
        await fetchData()
    }

    func deleteInvoice(id: String) async throws {
        try await service.deleteInvoice(id: id)
        await fetchData()
    }

    private func fetchData() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let inv       = service.fetchInvoices()
            async let items     = service.fetchInvoiceItems()
            async let movements = service.fetchStockMovementItems()
            invoices           = try await inv
            invoiceItems       = try await items
            stockMovementItems = await movements
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: "sales_lastSync")
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
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
}
