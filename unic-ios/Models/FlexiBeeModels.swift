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

struct FlexiBeeStockWithPrice: Identifiable, Hashable {
    let id = UUID()
    let card: FlexiBeeStockCard
    let price: FlexiBeeCenikItem?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

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

// MARK: - Payment Status

enum PaymentStatus: String, CaseIterable {
    case paid    = "uhrazeno"
    case partial = "castecneUhrazeno"
    case unpaid  = "neuhrazeno"
    case overdue

    var label: String {
        switch self {
        case .paid:    return String.payment_paid
        case .partial: return String.payment_partial
        case .unpaid:  return String.payment_unpaid
        case .overdue: return String.payment_overdue
        }
    }

    var color: Color {
        switch self {
        case .paid:    return .green
        case .partial: return .orange
        case .unpaid:  return .secondary
        case .overdue: return .red
        }
    }
}

// MARK: - Invoice

struct FlexiBeeInvoice: Identifiable, Codable {
    let id: String
    let kod: String?
    let popis: String?
    let datVyst: String?
    let datSplat: String?
    let sumCelkem: String?
    let stavUhrK: String?
    let firmaShowAs: String?

    enum CodingKeys: String, CodingKey {
        case id, kod, popis, datVyst, datSplat, sumCelkem, stavUhrK
        case firmaShowAs = "firma@showAs"
    }

    var total: Double         { Double(sumCelkem ?? "") ?? 0 }
    var issueDate: Date?      { Self.parseDate(datVyst) }
    var dueDate: Date?        { Self.parseDate(datSplat) }
    var invoiceNumber: String { kod ?? id }

    var clientName: String {
        guard let raw = firmaShowAs, let range = raw.range(of: ": ") else { return firmaShowAs ?? "—" }
        return String(raw[range.upperBound...])
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    var paymentStatus: PaymentStatus {
        let s = stavUhrK ?? ""
        if s.contains("castecne") { return .partial }
        if s.contains("uhrazeno") { return .paid }
        if let due = dueDate, due < Date() { return .overdue }
        return .unpaid
    }
}

struct FlexiBeeInvoicesWrapper: Decodable {
    let invoices: [FlexiBeeInvoice]
    enum CodingKeys: String, CodingKey { case invoices = "faktura-vydana" }
}

// MARK: - Invoice Line Item

struct FlexiBeeInvoiceItem: Identifiable, Codable {
    let id: String
    let kod: String?
    let nazev: String?
    let datVyst: String?
    let mnozMj: String?
    let sumCelkem: String?

    var quantity: Double    { Double(mnozMj    ?? "") ?? 0 }
    var total: Double       { Double(sumCelkem ?? "") ?? 0 }
    var productCode: String { kod ?? "" }
    var productName: String { nazev ?? kod ?? "—" }
    var isValid: Bool       { !productCode.isEmpty && quantity > 0 }

    var date: Date? {
        guard let s = datVyst else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

struct FlexiBeeInvoiceItemsWrapper: Decodable {
    let items: [FlexiBeeInvoiceItem]
    enum CodingKeys: String, CodingKey { case items = "faktura-vydana-polozka" }
}
