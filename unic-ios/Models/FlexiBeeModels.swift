import Foundation
import SwiftUI

// MARK: - Price List (Ceník)

struct FlexiBeeCenikItem: Identifiable, Codable {
    let id: String
    let kod: String
    let nazev: String?
    let cenaZaklVcDph: String?
    let nakupCena: String?

    var sellPriceVAT: Double { Double(cenaZaklVcDph ?? "") ?? 0 }
    var purchasePrice: Double { Double(nakupCena ?? "") ?? 0 }
    var displayName: String { nazev ?? kod }

    var marginPercent: Double? {
        guard purchasePrice > 0, sellPriceVAT > 0 else { return nil }
        let sellNet = sellPriceVAT / 1.21
        return (sellNet - purchasePrice) / sellNet * 100
    }
}

// MARK: - Stock (Skladová karta)

struct FlexiBeeStockCard: Identifiable, Codable {
    let id: UUID
    let kod: String
    let nazev: String
    let quantity: Double

    init(kod: String, nazev: String, quantity: Double) {
        self.id = UUID()
        self.kod = kod
        self.nazev = nazev
        self.quantity = quantity
    }
}

struct FlexiBeeStockWrapper: Decodable {
    let cards: [FlexiBeeStockRaw]

    enum CodingKeys: String, CodingKey {
        case cards = "skladova-karta"
    }
}

struct FlexiBeeStockRaw: Decodable {
    let cenikShowAs: String?
    let stavMjSPozadavky: String?

    enum CodingKeys: String, CodingKey {
        case cenikShowAs = "cenik@showAs"
        case stavMjSPozadavky
    }

    func toCard() -> FlexiBeeStockCard {
        var kod = ""
        var nazev = ""
        if let showAs = cenikShowAs, let range = showAs.range(of: ": ") {
            kod = String(showAs[showAs.startIndex..<range.lowerBound])
            nazev = String(showAs[range.upperBound...])
        } else {
            nazev = cenikShowAs ?? ""
        }
        return FlexiBeeStockCard(
            kod: kod,
            nazev: nazev,
            quantity: Double(stavMjSPozadavky ?? "") ?? 0
        )
    }
}

// MARK: - Response Wrappers

struct FlexiBeeResponse<T: Decodable>: Decodable {
    let winstrom: T
}

struct FlexiBeeCenikWrapper: Decodable {
    let cenik: [FlexiBeeCenikItem]
}

// MARK: - Joined Stock + Price

struct FlexiBeeStockWithPrice: Identifiable {
    let id = UUID()
    let card: FlexiBeeStockCard
    let price: FlexiBeeCenikItem?

    var kod: String { card.kod }
    var nazev: String { card.nazev }
    var quantity: Double { card.quantity }
    var sellPriceVAT: Double { price?.sellPriceVAT ?? 0 }
    var purchasePrice: Double { price?.purchasePrice ?? 0 }
    var marginPercent: Double? { price?.marginPercent }
}

struct FlexiBeeErrorResponse: Decodable {
    let winstrom: Winstrom
    struct Winstrom: Decodable {
        let success: String?
        let message: String?
    }
}
