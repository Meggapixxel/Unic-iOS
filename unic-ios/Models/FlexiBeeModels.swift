import Foundation
import SwiftUI

// MARK: - Price List

struct FlexiBeeCenikItem: Identifiable, Codable {
    let id: String
    let code: String
    let name: String?
    private let priceWithVATRaw: String?
    private let purchasePriceRaw: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code             = "kod"
        case name             = "nazev"
        case priceWithVATRaw  = "cenaZaklVcDph"
        case purchasePriceRaw = "nakupCena"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    var sellPriceVAT: Double  { Double(priceWithVATRaw  ?? "") ?? 0 }
    var purchasePrice: Double { Double(purchasePriceRaw ?? "") ?? 0 }
    var displayName: String   { name ?? code }

    var marginPercent: Double? {
        guard purchasePrice > 0, sellPriceVAT > 0 else { return nil }
        let sellNet = sellPriceVAT / 1.21
        return (sellNet - purchasePrice) / sellNet * 100
    }
}

// MARK: - Stock

struct FlexiBeeStockCard: Identifiable, Codable {
    let id: UUID
    let code: String
    let name: String
    let quantity: Double

    init(code: String, name: String, quantity: Double) {
        self.id       = UUID()
        self.code     = code
        self.name     = name
        self.quantity = quantity
    }
}

struct FlexiBeeStockWrapper: Decodable {
    let cards: [FlexiBeeStockRaw]
    enum CodingKeys: String, CodingKey { case cards = "skladova-karta" }
}

struct FlexiBeeStockRaw: Decodable {
    private let priceListRef:        String?
    private let quantityWithDemand:  String?

    enum CodingKeys: String, CodingKey {
        case priceListRef       = "cenik@showAs"
        case quantityWithDemand = "stavMjSPozadavky"
    }

    // "cenik" is FlexiBee shorthand that expands to "cenik@showAs" in response — cannot derive from CodingKeys
    static let requestFields = "cenik,stavMjSPozadavky"

    func toCard() -> FlexiBeeStockCard {
        var code = ""
        var name = ""
        if let ref = priceListRef, let range = ref.range(of: ": ") {
            code = String(ref[ref.startIndex..<range.lowerBound])
            name = String(ref[range.upperBound...])
        } else {
            name = priceListRef ?? ""
        }
        return FlexiBeeStockCard(
            code:     code,
            name:     name,
            quantity: Double(quantityWithDemand ?? "") ?? 0
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
    let card:  FlexiBeeStockCard
    let price: FlexiBeeCenikItem?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var code:          String  { card.code }
    var name:          String  { card.name }
    var quantity:      Double  { card.quantity }
    var sellPriceVAT:  Double  { price?.sellPriceVAT  ?? 0 }
    var purchasePrice: Double  { price?.purchasePrice ?? 0 }
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

struct FlexiBeeInvoice: Identifiable, Codable, Hashable {
    let id:                String
    let code:              String?
    let notes:             String?
    private let issueDateRaw:      String?
    private let dueDateRaw:        String?
    private let totalRaw:          String?
    private let paymentStatusCode: String?
    private let clientRef:         String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code              = "kod"
        case notes             = "popis"
        case issueDateRaw      = "datVyst"
        case dueDateRaw        = "datSplat"
        case totalRaw          = "sumCelkem"
        case paymentStatusCode = "stavUhrK"
        case clientRef         = "firma@showAs"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    var total:         Double  { Double(totalRaw ?? "") ?? 0 }
    var issueDate:     Date?   { Self.parseDate(issueDateRaw) }
    var dueDate:       Date?   { Self.parseDate(dueDateRaw) }
    var invoiceNumber: String  { code ?? id }

    var clientName: String {
        guard let raw = clientRef, let range = raw.range(of: ": ") else { return clientRef ?? "—" }
        return String(raw[range.upperBound...])
    }

    var clientCode: String? {
        guard let raw = clientRef, let range = raw.range(of: ": ") else { return nil }
        return String(raw[raw.startIndex..<range.lowerBound])
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    var paymentStatus: PaymentStatus {
        let s = paymentStatusCode ?? ""
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
    private let codeRaw:       String?
    private let nameRaw:       String?
    private let issueDateRaw:  String?
    private let quantityRaw:   String?
    private let totalRaw:      String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case codeRaw      = "kod"
        case nameRaw      = "nazev"
        case issueDateRaw = "datVyst"
        case quantityRaw  = "mnozMj"
        case totalRaw     = "sumCelkem"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    var quantity:    Double  { Double(quantityRaw ?? "") ?? 0 }
    var total:       Double  { Double(totalRaw    ?? "") ?? 0 }
    var productCode: String  { codeRaw ?? "" }
    var productName: String  { nameRaw ?? codeRaw ?? "—" }
    var isValid:     Bool    { !productCode.isEmpty && quantity > 0 }

    var date: Date? {
        guard let s = issueDateRaw else { return nil }
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

// MARK: - Firm (Client / Address Book)

struct FlexiBeeFirm: Identifiable, Decodable {
    let id:   String
    let code: String
    let name: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code = "kod"
        case name = "nazev"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    var displayName: String {
        let n = name ?? ""
        return n.isEmpty ? code : n
    }
}

struct FlexiBeeFirmWrapper: Decodable {
    let firms: [FlexiBeeFirm]
    enum CodingKeys: String, CodingKey { case firms = "adresar" }
}

// MARK: - Create Invoice Request

struct NewInvoiceLine: Encodable {
    let name:      String
    let quantity:  Double
    let unitPrice: Double
    let vatRate:   Double
    let priceType: String

    enum CodingKeys: String, CodingKey {
        case name      = "nazev"
        case quantity  = "mnozMj"
        case unitPrice = "cenaMj"
        case vatRate   = "sazDph"
        case priceType = "typCenyDphK"
    }

    init(name: String, quantity: Double, unitPrice: Double, vatRate: Double = 21.0) {
        self.name      = name
        self.quantity  = quantity
        self.unitPrice = unitPrice
        self.vatRate   = vatRate
        self.priceType = "typCeny.sDph"
    }
}

struct NewInvoice: Encodable {
    let documentType: String
    let clientCode:   String
    let issueDate:    String
    let dueDate:      String
    let notes:        String?
    let lineItems:    [NewInvoiceLine]

    enum CodingKeys: String, CodingKey {
        case documentType = "typDokl"
        case clientCode   = "firma"
        case issueDate    = "datVyst"
        case dueDate      = "datSplat"
        case notes        = "popis"
        case lineItems    = "polozkyFaktury"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(documentType,       forKey: .documentType)
        try c.encode(clientCode,         forKey: .clientCode)
        try c.encode(issueDate,          forKey: .issueDate)
        try c.encode(dueDate,            forKey: .dueDate)
        try c.encodeIfPresent(notes,     forKey: .notes)
        try c.encode(lineItems,          forKey: .lineItems)
    }
}

struct CreateInvoiceEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let fakturaVydana: [NewInvoice]
        enum CodingKeys: String, CodingKey { case fakturaVydana = "faktura-vydana" }
    }
}
