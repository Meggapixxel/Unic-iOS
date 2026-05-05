import Foundation
import SwiftUI
import Combine
import IdentifiedCollections

enum FlexiBeeError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return String.error_network(e.localizedDescription)
        case .decodingError(let e): return String.error_parsing(e.localizedDescription)
        case .apiError(let msg):   return String.error_api(msg)
        case .httpError(let code): return String.error_http(code)
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

    private static let cacheTTL: TimeInterval = 60 * 60
    private static let stockKey  = "flexibee_cache_stock"
    private static let pricesKey = "flexibee_cache_prices"

    private init() {
        restoreFromDisk()
    }

    // MARK: - Computed

    var isCacheValid: Bool {
        guard let last = lastSyncDate else { return false }
        return Date().timeIntervalSince(last) < Self.cacheTTL
    }

    var stockWithPrices: IdentifiedArrayOf<FlexiBeeStockWithPrice> {
        let priceByCode = Dictionary(uniqueKeysWithValues: priceList.map { ($0.code, $0) })
        return IdentifiedArray(uniqueElements: stock.map { FlexiBeeStockWithPrice(card: $0, price: priceByCode[$0.code]) })
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

    func fetchInvoiceItems() async throws -> [FlexiBeeInvoiceItem] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoiceItemsWrapper>.self,
            path: "/faktura-vydana-polozka.json",
            fields: FlexiBeeInvoiceItem.apiFields,
            limit: 5000,
            order: "datVyst@D"
        )
        return response.winstrom.items.filter { $0.isValid }
    }

    func fetchInvoices() async throws -> [FlexiBeeInvoice] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoicesWrapper>.self,
            path: "/faktura-vydana.json",
            fields: FlexiBeeInvoice.apiFields,
            limit: 1000,
            order: "datVyst@D"
        )
        return response.winstrom.invoices
    }

    func fetchFirms() async throws -> [FlexiBeeFirm] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeFirmWrapper>.self,
            path: "/adresar.json",
            fields: FlexiBeeFirm.apiFields,
            limit: 500
        )
        return response.winstrom.firms
            .filter { !$0.code.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func fetchLineItemsForInvoice(_ invoiceId: String) async throws -> [FlexiBeeInvoiceItem] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoiceItemsWrapper>.self,
            path: "/faktura-vydana/\(invoiceId)/faktura-vydana-polozka.json",
            fields: FlexiBeeInvoiceItem.apiFields,
            limit: 100
        )
        return response.winstrom.items
    }

    func createInvoice(_ invoice: NewInvoice) async throws {
        try await postInvoice(to: baseURL + "/faktura-vydana.json", invoice: invoice, method: "POST")
    }

    func updateInvoice(id: String, invoice: NewInvoice) async throws {
        try await postInvoice(to: baseURL + "/faktura-vydana/\(id).json", invoice: invoice, method: "PUT")
    }

    func updateInvoicePaymentStatus(id: String, status: PaymentStatus) async throws {
        guard status != .overdue else { return }
        let code: String
        switch status {
        case .paid:    code = "code:uhrazeno"
        case .partial: code = "code:castecneUhrazeno"
        case .unpaid:  code = "code:neuhrazeno"
        case .overdue: return
        }
        let envelope = PaymentStatusEnvelope(winstrom: .init(fakturaVydana: [.init(id: id, stavUhrK: code)]))
        let data = try JSONEncoder().encode(envelope)
        guard let url = URL(string: baseURL + "/faktura-vydana/\(id).json") else {
            throw FlexiBeeError.apiError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        request.timeoutInterval = 30
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlexiBeeError.httpError(0) }
        guard (200...201).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(FlexiBeeErrorResponse.self, from: responseData) {
                throw FlexiBeeError.apiError(err.winstrom.message ?? "HTTP \(http.statusCode)")
            }
            throw FlexiBeeError.httpError(http.statusCode)
        }
    }

    func fetchSingleInvoice(id: String) async throws -> FlexiBeeInvoice? {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoicesWrapper>.self,
            path: "/faktura-vydana/\(id).json",
            fields: FlexiBeeInvoice.apiFields,
            limit: 1
        )
        return response.winstrom.invoices.first
    }

    private func postInvoice(to urlString: String, invoice: NewInvoice, method: String) async throws {
        let envelope = CreateInvoiceEnvelope(winstrom: .init(fakturaVydana: [invoice]))
        let data = try JSONEncoder().encode(envelope)

        guard let url = URL(string: urlString) else {
            throw FlexiBeeError.apiError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        request.timeoutInterval = 30

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FlexiBeeError.httpError(0)
        }
        guard (200...201).contains(http.statusCode) else {
            if let errResp = try? JSONDecoder().decode(FlexiBeeErrorResponse.self, from: responseData) {
                throw FlexiBeeError.apiError(errResp.winstrom.message ?? "HTTP \(http.statusCode)")
            }
            throw FlexiBeeError.httpError(http.statusCode)
        }
    }

    func fetchStockMovementItems() async -> [FlexiBeeStockMovementItem] {
        // Step 1: fetch all movement headers, keep only outflows (S- prefix)
        guard let headers = try? await fetch(
            FlexiBeeResponse<FlexiBeeStockMovementWrapper>.self,
            path: "/skladovy-pohyb.json",
            fields: "id,kod",
            limit: 1000
        ) else { return [] }
        let outflowIds = headers.winstrom.movements
            .filter { $0.code.hasPrefix("S-") }
            .map { $0.id }

        guard !outflowIds.isEmpty else { return [] }

        // Step 2: fetch line items for each outflow document concurrently
        return await withTaskGroup(of: [FlexiBeeStockMovementItem].self) { group in
            for id in outflowIds {
                group.addTask {
                    guard let response = try? await self.fetch(
                        FlexiBeeResponse<FlexiBeeStockMovementItemsWrapper>.self,
                        path: "/skladovy-pohyb/\(id)/skladovy-pohyb-polozka.json",
                        fields: FlexiBeeStockMovementItem.apiFields,
                        limit: 500
                    ) else { return [] }
                    return response.winstrom.items.filter { $0.isValid }
                }
            }
            var all: [FlexiBeeStockMovementItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    func fetchPriceList() async throws -> [FlexiBeeCenikItem] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeCenikWrapper>.self,
            path: "/cenik.json",
            fields: FlexiBeeCenikItem.apiFields,
            limit: 300
        )
        return response.winstrom.cenik
    }

    func fetchStock() async throws -> [FlexiBeeStockCard] {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeStockWrapper>.self,
            path: "/skladova-karta.json",
            fields: FlexiBeeStockRaw.requestFields,
            limit: 300
        )
        return response.winstrom.cards.map { $0.toCard() }
    }

    // MARK: - HTTP

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        fields: String,
        limit: Int,
        order: String? = nil,
        filterBy: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw FlexiBeeError.apiError("Invalid URL path: \(path)")
        }
        var queryItems = [
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit",  value: String(limit))
        ]
        if let order { queryItems.append(URLQueryItem(name: "order", value: order)) }
        if let filter = filterBy { queryItems.append(URLQueryItem(name: "where", value: filter)) }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw FlexiBeeError.apiError("Failed to build URL for path: \(path)")
        }
        var request = URLRequest(url: url)
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

// MARK: - Private types for payment status update

private struct PaymentStatusItem: Encodable {
    let id: String
    let stavUhrK: String
}

private struct PaymentStatusEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let fakturaVydana: [PaymentStatusItem]
        enum CodingKeys: String, CodingKey { case fakturaVydana = "faktura-vydana" }
    }
}
