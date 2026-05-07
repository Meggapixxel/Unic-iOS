import Foundation
import SwiftUI
import Combine
import IdentifiedCollections

enum FlexiBeeError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    case httpError(Int)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return String.error_network(e.localizedDescription)
        case .decodingError(let e): return String.error_parsing(e.localizedDescription)
        case .apiError(let msg):   return String.error_api(msg)
        case .httpError(let code): return String.error_http(code)
        case .unauthorized:        return String.error_unauthorized
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

    private func require(_ permission: Bool) throws {
        guard permission else { throw FlexiBeeError.unauthorized }
    }

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

        do { stock = try await stockTask } catch { errors.append(String.error_fetch_stock) }
        do { priceList = try await pricesTask } catch { errors.append(String.error_fetch_prices) }

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
            order: "datVyst@D",
            detail: true
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

    @discardableResult
    func createInvoice(_ invoice: NewInvoice) async throws -> String {
        try require(AuthService.shared.canCreateInvoice)
        return try await postInvoice(to: baseURL + "/faktura-vydana.json", invoice: invoice, method: "POST")
    }

    func updateInvoice(id: String, invoice: NewInvoice) async throws {
        try require(AuthService.shared.canEditInvoice)
        try await postInvoice(to: baseURL + "/faktura-vydana/\(id).json", invoice: invoice, method: "PUT")
    }

    func updateInvoicePaymentStatus(id: String, status: PaymentStatus, method: PaymentMethod = .prevod) async throws {
        try require(AuthService.shared.canEditInvoice)
        guard status == .paid else { return }
        let item = PaymentStatusItem(id: id, stavUhrK: "stavUhr.uhrazenoRucne", formaUhradyCis: method.rawValue)
        let envelope = PaymentStatusEnvelope(winstrom: .init(fakturaVydana: [item]))
        let body = try JSONEncoder().encode(envelope)
        _ = try await execute(method: "PUT", urlString: baseURL + "/faktura-vydana/\(id).json", body: body)
    }

    func createCashReceipt(for invoice: FlexiBeeInvoice) async throws {
        guard let clientCode = invoice.clientCode else { return }
        let receipt = NewCashReceipt(
            clientCode:  clientCode,
            description: "Platba za \(invoice.invoiceNumber)",
            varSym:      invoice.varSym ?? "",
            total:       invoice.total
        )
        let envelope = CreateCashReceiptEnvelope(winstrom: .init(pokladniPohyb: [receipt]))
        let body = try JSONEncoder().encode(envelope)
        _ = try await execute(method: "POST", urlString: baseURL + "/pokladni-pohyb.json", body: body)
    }

    func fetchPDF(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw FlexiBeeError.apiError("Invalid URL") }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FlexiBeeError.apiError("PDF fetch failed")
        }
        return data
    }

    func fetchCashReceiptId(for invoiceNumber: String) async throws -> String? {
        let encoded = invoiceNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? invoiceNumber
        let response = try await fetch(
            FlexiBeeResponse<CashReceiptListWrapper>.self,
            path: "/pokladni-pohyb/(\(encoded)).json",
            fields: "id,popis",
            limit: 10
        )
        return response.winstrom.items.first(where: { $0.popis?.contains(invoiceNumber) == true })?.id
    }

    // Creates a STANDARD stock movement (vydej). typDokl must be "code:STANDARD".
    // Returns the FlexiBee internal ID of the created movement.
    @discardableResult
    func createStockMovement(_ movement: NewStockMovement) async throws -> String {
        try require(AuthService.shared.canCreateStockMovement)
        let envelope = CreateStockMovementEnvelope(winstrom: .init(skladovyPohyb: [movement]))
        let body = try JSONEncoder().encode(envelope)
        let data = try await execute(method: "POST", urlString: baseURL + "/skladovy-pohyb.json", body: body)
        let result = try JSONDecoder().decode(FlexiBeeCreateResponse.self, from: data)
        guard let id = result.winstrom.results.first?.id else {
            throw FlexiBeeError.apiError("No ID in stock movement response")
        }
        return id
    }

    func fetchInvoiceNumber(id: String) async throws -> String? {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoicesWrapper>.self,
            path: "/faktura-vydana/\(id).json",
            fields: "id,kod",
            limit: 1
        )
        return response.winstrom.invoices.first?.invoiceNumber
    }

    func deleteInvoice(id: String) async throws {
        try require(AuthService.shared.canDeleteInvoice)
        _ = try await execute(method: "DELETE", urlString: baseURL + "/faktura-vydana/\(id).json", successRange: 200...204)
    }

    func deleteFirm(id: String) async throws {
        try require(AuthService.shared.canDeleteClient)
        _ = try await execute(method: "DELETE", urlString: baseURL + "/adresar/\(id).json", successRange: 200...204)
    }

    func createFirm(_ firm: NewFirm) async throws -> FlexiBeeFirm {
        try require(AuthService.shared.canCreateClient)
        let envelope = CreateFirmEnvelope(winstrom: .init(adresar: [firm]))
        let body = try JSONEncoder().encode(envelope)
        let responseData = try await execute(method: "POST", urlString: baseURL + "/adresar.json", body: body)
        let result = try JSONDecoder().decode(FlexiBeeCreateResponse.self, from: responseData)
        guard let id = result.winstrom.results.first?.id else {
            throw FlexiBeeError.apiError("No ID in response")
        }
        let firmResponse = try await fetch(
            FlexiBeeResponse<FlexiBeeFirmWrapper>.self,
            path: "/adresar/\(id).json",
            fields: FlexiBeeFirm.apiFields,
            limit: 1
        )
        guard let created = firmResponse.winstrom.firms.first else {
            throw FlexiBeeError.apiError("Created firm not found")
        }
        return created
    }

    func fetchSingleInvoice(id: String) async throws -> FlexiBeeInvoice? {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeInvoicesWrapper>.self,
            path: "/faktura-vydana/\(id).json",
            fields: FlexiBeeInvoice.apiFields,
            limit: 1,
            detail: true
        )
        return response.winstrom.invoices.first
    }

    @discardableResult
    private func postInvoice(to urlString: String, invoice: NewInvoice, method: String) async throws -> String {
        let envelope = CreateInvoiceEnvelope(winstrom: .init(fakturaVydana: [invoice]))
        let body = try JSONEncoder().encode(envelope)
        let data = try await execute(method: method, urlString: urlString, body: body)
        let result = try JSONDecoder().decode(FlexiBeeCreateResponse.self, from: data)
        return result.winstrom.results.first?.id ?? ""
    }

    /// Fetches the stock movement for an invoice by description, plus its line items.
    /// Returns nil when no movement exists yet (e.g. before "Paid" is pressed).
    func fetchStockMovement(for invoiceNumber: String) async throws -> (movement: FlexiBeeStockMovement, items: [FlexiBeeStockMovementItem])? {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeStockMovementWrapper>.self,
            path: "/skladovy-pohyb.json",
            fields: "id,kod",
            limit: 1,
            filterBy: "popis='Vydej k \(invoiceNumber)'"
        )
        guard let header = response.winstrom.movements.first else { return nil }
        let itemsResponse = try await fetch(
            FlexiBeeResponse<FlexiBeeStockMovementItemsWrapper>.self,
            path: "/skladovy-pohyb/\(header.id)/skladovy-pohyb-polozka.json",
            fields: FlexiBeeStockMovementItem.apiFields,
            limit: 500
        )
        let items = itemsResponse.winstrom.items.filter { $0.isValid }
        return (header, items)
    }

    func deleteStockMovement(for invoiceNumber: String) async throws {
        let response = try await fetch(
            FlexiBeeResponse<FlexiBeeStockMovementWrapper>.self,
            path: "/skladovy-pohyb.json",
            fields: "id",
            limit: 1,
            filterBy: "popis='Vydej k \(invoiceNumber)'"
        )
        guard let id = response.winstrom.movements.first?.id else { return }
        try await deleteOrStornoMovement(id: id)
    }

    func deleteStockMovementById(_ id: String) async throws {
        try await deleteOrStornoMovement(id: id)
    }

    private func deleteOrStornoMovement(id: String) async throws {
        do {
            _ = try await execute(method: "DELETE", urlString: baseURL + "/skladovy-pohyb/\(id).json", successRange: 200...204)
        } catch {
            // FIFO references block DELETE — storno creates a reverse document instead
            _ = try await execute(method: "GET", urlString: baseURL + "/skladovy-pohyb/\(id).json?action=storno", successRange: 200...201)
        }
    }

    func fetchStockMovementItems() async throws -> [FlexiBeeStockMovementItem] {
        // Step 1: fetch all movement headers, keep only outflows (S- prefix)
        let headers = try await fetch(
            FlexiBeeResponse<FlexiBeeStockMovementWrapper>.self,
            path: "/skladovy-pohyb.json",
            fields: "id,kod",
            limit: 1000
        )
        let outflowIds = headers.winstrom.movements
            .filter { $0.code.hasPrefix("S-") }
            .map { $0.id }

        guard !outflowIds.isEmpty else { return [] }

        // Step 2: fetch line items for each outflow document concurrently
        return await withTaskGroup(of: [FlexiBeeStockMovementItem].self) { group in
            for id in outflowIds {
                group.addTask {
                    do {
                        let response = try await self.fetch(
                            FlexiBeeResponse<FlexiBeeStockMovementItemsWrapper>.self,
                            path: "/skladovy-pohyb/\(id)/skladovy-pohyb-polozka.json",
                            fields: FlexiBeeStockMovementItem.apiFields,
                            limit: 500
                        )
                        return response.winstrom.items.filter { $0.isValid }
                    } catch {
                        return []
                    }
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

    // MARK: - HTTP Helpers

    /// Throws `FlexiBeeError.apiError` or `.httpError` when status is outside `successRange`.
    /// Digs into `results[].errors[]` for the most specific FlexiBee message.
    private func validateResponse(_ statusCode: Int, data: Data, successRange: ClosedRange<Int> = 200...201) throws {
        guard successRange.contains(statusCode) else {
            if let err = try? JSONDecoder().decode(FlexiBeeErrorResponse.self, from: data) {
                throw FlexiBeeError.apiError(err.errorMessage ?? "HTTP \(statusCode)")
            }
            throw FlexiBeeError.httpError(statusCode)
        }
    }

    /// Executes a mutating request (POST / PUT / DELETE) and returns the raw response `Data`.
    @discardableResult
    private func execute(
        method: String,
        urlString: String,
        body: Data? = nil,
        successRange: ClosedRange<Int> = 200...201
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw FlexiBeeError.apiError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 30

        let path = url.path
        AppLogger.log(.info, "FlexiBee", "→ \(method) \(path)")

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else { throw FlexiBeeError.httpError(0) }

        if successRange.contains(http.statusCode) {
            AppLogger.log(.info, "FlexiBee", "← \(http.statusCode) \(method) \(path) (\(ms)ms, \(data.count)B)")
        } else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            AppLogger.log(.error, "FlexiBee", "← \(http.statusCode) \(method) \(path) (\(ms)ms) | \(preview)")
        }

        try validateResponse(http.statusCode, data: data, successRange: successRange)
        return data
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        fields: String,
        limit: Int,
        order: String? = nil,
        filterBy: String? = nil,
        detail: Bool = false
    ) async throws -> T {
        // FlexiBee FQL filter must be a URL path segment: /evidence/(filter).json
        // NOT a query parameter — the ?where= approach is silently ignored.
        let basePath: String
        if let filter = filterBy {
            let stripped = path.hasSuffix(".json") ? String(path.dropLast(5)) : path
            // Encode filter for safe embedding in a URL path segment.
            // '/' must be encoded as %2F so it isn't treated as a path separator.
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/")
            let encoded = filter.addingPercentEncoding(withAllowedCharacters: allowed) ?? filter
            basePath = "\(stripped)/(\(encoded)).json"
        } else {
            basePath = path
        }
        guard var components = URLComponents(string: baseURL + basePath) else {
            throw FlexiBeeError.apiError("Invalid URL path: \(basePath)")
        }
        var queryItems = [
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit",  value: String(limit))
        ]
        if let order  { queryItems.append(URLQueryItem(name: "order",  value: order)) }
        if detail     { queryItems.append(URLQueryItem(name: "detail", value: "full")) }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw FlexiBeeError.apiError("Failed to build URL for path: \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let path = url.path
        AppLogger.log(.debug, "FlexiBee", "→ GET \(path)")

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else { throw FlexiBeeError.httpError(0) }

        if http.statusCode == 200 {
            AppLogger.log(.debug, "FlexiBee", "← \(http.statusCode) GET \(path) (\(ms)ms, \(data.count)B)")
        } else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            AppLogger.log(.error, "FlexiBee", "← \(http.statusCode) GET \(path) (\(ms)ms) | \(preview)")
        }

        try validateResponse(http.statusCode, data: data, successRange: 200...200)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLogger.log(.error, "FlexiBee", "Decode error for \(path): \(error)")
            throw FlexiBeeError.decodingError(error)
        }
    }
}

// MARK: - Private types for payment status update

private struct PaymentStatusItem: Encodable {
    let id:             String
    let stavUhrK:       String
    let formaUhradyCis: String
}

private struct PaymentStatusEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let fakturaVydana: [PaymentStatusItem]
        enum CodingKeys: String, CodingKey { case fakturaVydana = "faktura-vydana" }
    }
}
