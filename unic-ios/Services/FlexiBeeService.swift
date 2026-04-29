import Foundation

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

final class FlexiBeeService {
    static let shared = FlexiBeeService()

    private let baseURL = "https://chariot-studio.flexibee.eu/c/chariot_studio_s_r_o_"

    private let authHeader: String = {
        let creds = "api:wuwtoh-jiqjix-puJqu7"
        return "Basic " + Data(creds.utf8).base64EncodedString()
    }()

    private init() {}

    // MARK: - Public API

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

    // MARK: - Private

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
