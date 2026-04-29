import Foundation
import SwiftUI
import Combine

enum FlexiBeeError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Помилка мережі: \(e.localizedDescription)"
        case .decodingError(let e): return "Помилка парсингу: \(e.localizedDescription)"
        case .apiError(let msg): return "Помилка API: \(msg)"
        case .httpError(let code): return "HTTP помилка \(code)"
        }
    }
}

@MainActor
final class FlexiBeeService: ObservableObject {
    static let shared = FlexiBeeService()

    private let baseURL = "https://chariot-studio.flexibee.eu/c/chariot_studio_s_r_o_"

    private let authHeader: String = {
        let creds = "api:wuwtoh-jiqjix-puJqu7"
        return "Basic " + Data(creds.utf8).base64EncodedString()
    }()

    @Published var stock: [FlexiBeeStockCard] = []
    @Published var priceList: [FlexiBeeCenikItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "flexibee_lastSync") as? Date

    private static let cacheTTL: TimeInterval = 24 * 60 * 60
    private static let stockKey = "flexibee_cache_stock"
    private static let pricesKey = "flexibee_cache_prices"

    private init() {
        restoreFromDisk()
    }

    // MARK: - Computed

    var isCacheValid: Bool {
        guard let last = lastSyncDate else { return false }
        return Date().timeIntervalSince(last) < Self.cacheTTL
    }

    var stockWithPrices: [FlexiBeeStockWithPrice] {
        let priceByKod = Dictionary(uniqueKeysWithValues: priceList.map { ($0.kod, $0) })
        return stock.map { FlexiBeeStockWithPrice(card: $0, price: priceByKod[$0.kod]) }
    }

    // MARK: - Load

    func loadIfNeeded() async {
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

        async let stockTask = fetchStock()
        async let pricesTask = fetchPriceList()

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

    func fetchPriceList() async throws -> [FlexiBeeCenikItem] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeCenikWrapper>.self,
            path: "/cenik.json",
            fields: "id,kod,nazev,cenaZaklVcDph,nakupCena",
            limit: 300
        )
        return response.winstrom.cenik
    }

    func fetchStock() async throws -> [FlexiBeeStockCard] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeStockWrapper>.self,
            path: "/skladova-karta.json",
            fields: "cenik,stavMjSPozadavky",
            limit: 300
        )
        return response.winstrom.cards.map { $0.toCard() }
    }

    // MARK: - HTTP

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        fields: String,
        limit: Int
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        components.queryItems = [
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw FlexiBeeError.httpError(0)
        }
        guard http.statusCode == 200 else {
            if let errResp = try? JSONDecoder().decode(FlexiBeeErrorResponse.self, from: data) {
                throw FlexiBeeError.apiError(errResp.winstrom.message ?? "Unknown error")
            }
            throw FlexiBeeError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FlexiBeeError.decodingError(error)
        }
    }
}
