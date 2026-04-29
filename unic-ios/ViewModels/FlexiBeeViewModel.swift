import Foundation
import SwiftUI
import Combine

@MainActor
final class FlexiBeeViewModel: ObservableObject {
    @Published var stock: [FlexiBeeStockCard] = []
    @Published var priceList: [FlexiBeeCenikItem] = []

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    @Published private(set) var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "flexibee_lastSync") as? Date

    private static let cacheTTL: TimeInterval = 24 * 60 * 60
    private static let stockKey = "flexibee_cache_stock"
    private static let pricesKey = "flexibee_cache_prices"
    private let service = FlexiBeeService.shared

    init() {
        restoreFromDisk()
    }

    var isCacheValid: Bool {
        guard let last = lastSyncDate else { return false }
        return Date().timeIntervalSince(last) < Self.cacheTTL
    }

    // MARK: - Computed: Stock + Prices (joined)

    private var stockWithPrices: [FlexiBeeStockWithPrice] {
        let priceByKod = Dictionary(uniqueKeysWithValues: priceList.map { ($0.kod, $0) })
        return stock.map { FlexiBeeStockWithPrice(card: $0, price: priceByKod[$0.kod]) }
    }

    var filteredStock: [FlexiBeeStockWithPrice] {
        let base: [FlexiBeeStockWithPrice]
        if searchText.isEmpty {
            base = stockWithPrices
        } else {
            let q = searchText.lowercased()
            base = stockWithPrices.filter {
                $0.kod.lowercased().contains(q) || $0.nazev.lowercased().contains(q)
            }
        }
        return base.sorted { $0.quantity > $1.quantity }
    }

    var totalStockUnits: Double { stock.reduce(0) { $0 + $1.quantity } }
    var lowStockCount: Int { stock.filter { $0.quantity <= 2 }.count }

    // MARK: - Load

    func loadIfNeeded() async {
        // Дані вже відновлені з диску в init() — якщо TTL валідний, нічого не робимо
        guard !isCacheValid else { return }
        await fetchAll()
    }

    func forceSync() async {
        await fetchAll()
    }

    // MARK: - Disk cache

    private func restoreFromDisk() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: Self.stockKey),
           let saved = try? decoder.decode([FlexiBeeStockCard].self, from: data) {
            stock = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.pricesKey),
           let saved = try? decoder.decode([FlexiBeeCenikItem].self, from: data) {
            priceList = saved
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(stock) {
            UserDefaults.standard.set(data, forKey: Self.stockKey)
        }
        if let data = try? encoder.encode(priceList) {
            UserDefaults.standard.set(data, forKey: Self.pricesKey)
        }
    }

    // MARK: - Network

    private func fetchAll() async {
        isLoading = true
        errorMessage = nil

        async let stockTask = service.fetchStock()
        async let pricesTask = service.fetchPriceList()

        var errors: [String] = []

        if let s = try? await stockTask { stock = s } else { errors.append("склад") }
        if let p = try? await pricesTask { priceList = p } else { errors.append("ціни") }

        if errors.isEmpty {
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: "flexibee_lastSync")
            saveToDisk()
        } else {
            errorMessage = "Не вдалося завантажити: \(errors.joined(separator: ", "))"
        }

        isLoading = false
    }

    func resetFilters() {
        searchText = ""
    }
}
