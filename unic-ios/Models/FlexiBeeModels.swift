import Foundation

private let _flexiBeeDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

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
    var unitPrice: String     { sellPriceVAT > 0 ? String(format: "%.0f", sellPriceVAT) : "" }

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

extension FlexiBeeResponse: Sendable where T: Sendable {}

struct FlexiBeeCenikWrapper: Decodable {
    let cenik: [FlexiBeeCenikItem]
}

// MARK: - Joined Stock + Price

struct FlexiBeeStockWithPrice: Identifiable, Hashable {
    let card:  FlexiBeeStockCard
    let price: FlexiBeeCenikItem?

    var id: String { card.code }

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
        let results: [Result]?

        struct Result: Decodable {
            let message: String?
            let errors:  [FieldError]?
            struct FieldError: Decodable {
                let message: String?
            }
        }
    }

    /// Extracts the most specific error message available in the response.
    var errorMessage: String? {
        if let m = winstrom.message, !m.isEmpty { return m }
        return winstrom.results?.compactMap { r in
            r.errors?.compactMap(\.message).first ?? r.message
        }.first
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

}

// MARK: - Invoice

struct FlexiBeeInvoice: Identifiable, Codable, Hashable {
    let id:                String
    let code:              String?
    let notes:             String?
    let finalText:         String?
    private let issueDateRaw:      String?
    private let dueDateRaw:        String?
    private let totalRaw:          String?
    private let paymentStatusCode: String?
    private let clientRef:         String?
    private let paymentMethodCode: String?
    let varSym:                    String?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code              = "kod"
        case notes             = "popis"
        case finalText         = "zavTxt"
        case issueDateRaw      = "datVyst"
        case dueDateRaw        = "datSplat"
        case totalRaw          = "sumCelkem"
        case paymentStatusCode = "stavUhrK"
        case clientRef         = "firma@showAs"
        case paymentMethodCode = "formaUhradyCis"
        case varSym            = "varSym"
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
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }

    var paymentMethod: PaymentMethod? { PaymentMethod(rawValue: paymentMethodCode ?? "") }

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
    private let cenikRef:      String?  // "code:CFB/220" — canonical price list code
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case codeRaw      = "kod"
        case nameRaw      = "nazev"
        case issueDateRaw = "datVyst"
        case quantityRaw  = "mnozMj"
        case totalRaw     = "sumCelkem"
        case cenikRef     = "cenik"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    var quantity:    Double  { Double(quantityRaw ?? "") ?? 0 }
    var total:       Double  { Double(totalRaw    ?? "") ?? 0 }
    var productCode: String  { codeRaw ?? "" }
    var productName: String  { nameRaw ?? codeRaw ?? "—" }
    var isValid:     Bool    { !productCode.isEmpty && quantity > 0 }

    // Canonical price list code (CFB/220), used for stock matching
    var cenikCode: String {
        guard let ref = cenikRef else { return productCode }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    // Non-nil only when the item has an explicit ceník reference (real stock item, not a bundle)
    var stockCode: String? {
        guard let ref = cenikRef, !ref.isEmpty else { return nil }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    var date: Date? {
        guard let s = issueDateRaw else { return nil }
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }
}

struct FlexiBeeInvoiceItemsWrapper: Decodable {
    let items: [FlexiBeeInvoiceItem]
    enum CodingKeys: String, CodingKey { case items = "faktura-vydana-polozka" }
}

// MARK: - Stock Movement (Warehouse outflow header)

struct FlexiBeeStockMovement: Decodable, Sendable {
    let id:    String
    let code:  String
    let notes: String?
    enum CodingKeys: String, CodingKey { case id; case code = "kod"; case notes = "popis" }
}

struct FlexiBeeStockMovementWrapper: Decodable, Sendable {
    let movements: [FlexiBeeStockMovement]
    enum CodingKeys: String, CodingKey { case movements = "skladovy-pohyb" }
}

// MARK: - Stock Movement Item (Warehouse outflow line)

struct FlexiBeeStockMovementItem: Identifiable, Codable, Sendable {
    let id:              String
    private let codeRaw: String?
    private let nameRaw: String?
    private let dateRaw: String?
    private let quantityRaw: String?
    private let totalRaw:    String?
    private let cenikRef:    String?  // "code:CFB/220" — canonical price-list code

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case codeRaw     = "kod"
        case nameRaw     = "nazev"
        case dateRaw     = "datVyst"
        case quantityRaw = "mnozMj"
        case totalRaw    = "sumCelkem"
        case cenikRef    = "cenik"
    }

    static var apiFields: String {
        CodingKeys.allCases.map(\.rawValue).joined(separator: ",")
    }

    var productCode:    String { codeRaw ?? "" }
    var productName:    String { nameRaw ?? codeRaw ?? "—" }
    var quantityIssued: Double { Double(quantityRaw ?? "") ?? 0 }
    var total:          Double { Double(totalRaw ?? "") ?? 0 }

    var cenikCode: String {
        guard let ref = cenikRef else { return productCode }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    var date: Date? {
        guard let s = dateRaw else { return nil }
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }

    var isValid: Bool { !productCode.isEmpty && quantityIssued > 0 }
}

struct FlexiBeeStockMovementItemsWrapper: Decodable, Sendable {
    let items: [FlexiBeeStockMovementItem]
    enum CodingKeys: String, CodingKey { case items = "skladovy-pohyb-polozka" }
}

// MARK: - Payment Method

enum PaymentMethod: String, CaseIterable {
    case prevod = "code:PREVOD"
    case hotove = "code:HOTOVE"
    case karta  = "code:KARTA"

    var displayName: String {
        switch self {
        case .prevod: return String.payment_method_prevod
        case .hotove: return String.payment_method_hotove
        case .karta:  return String.payment_method_karta
        }
    }

    var icon: String {
        switch self {
        case .prevod: return "building.columns"
        case .hotove: return "banknote"
        case .karta:  return "creditcard"
        }
    }
}

// MARK: - Firm (Client / Address Book)

struct FlexiBeeFirm: Identifiable, Decodable, Equatable {
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
    let name:        String
    let productCode: String?
    let quantity:    Double
    let unitPrice:   Double
    let vatRate:     Double
    let priceType:   String

    enum CodingKeys: String, CodingKey {
        case name        = "nazev"
        case productCode = "cenik"
        case quantity    = "mnozMj"
        case unitPrice   = "cenaMj"
        case vatRate     = "sazDph"
        case priceType   = "typCenyDphK"
        case zdrojProSkl
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,             forKey: .name)
        try c.encodeIfPresent(productCode.map { "code:\($0)" }, forKey: .productCode)
        try c.encode(quantity,         forKey: .quantity)
        try c.encode(unitPrice,        forKey: .unitPrice)
        try c.encode(vatRate,          forKey: .vatRate)
        try c.encode(priceType,        forKey: .priceType)
        try c.encode(false,            forKey: .zdrojProSkl)
    }

    init(name: String, productCode: String? = nil, quantity: Double, unitPrice: Double, vatRate: Double = 21.0) {
        self.name        = name
        self.productCode = productCode
        self.quantity    = quantity
        self.unitPrice   = unitPrice
        self.vatRate     = vatRate
        self.priceType   = "typCeny.sDph"
    }
}

struct NewInvoice: Encodable {
    let documentType:  String
    let clientCode:    String
    let issueDate:     String
    let dueDate:       String
    let notes:         String?
    let paymentMethod: String
    let lineItems:     [NewInvoiceLine]

    enum CodingKeys: String, CodingKey {
        case documentType  = "typDokl"
        case clientCode    = "firma"
        case issueDate     = "datVyst"
        case dueDate       = "datSplat"
        case notes         = "popis"
        case paymentMethod = "formaUhradyCis"
        case lineItems     = "polozkyFaktury"
        case zdrojProSkl
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(documentType,       forKey: .documentType)
        try c.encode(clientCode,         forKey: .clientCode)
        try c.encode(issueDate,          forKey: .issueDate)
        try c.encode(dueDate,            forKey: .dueDate)
        try c.encodeIfPresent(notes,     forKey: .notes)
        try c.encode(paymentMethod,      forKey: .paymentMethod)
        try c.encode(lineItems,          forKey: .lineItems)
        try c.encode(false,              forKey: .zdrojProSkl)
    }
}

struct CreateInvoiceEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let fakturaVydana: [NewInvoice]
        enum CodingKeys: String, CodingKey { case fakturaVydana = "faktura-vydana" }
    }
}

// MARK: - Create Stock Movement Request

struct NewStockMovementLine: Encodable {
    let productCode: String
    let quantity:    Double

    enum CodingKeys: String, CodingKey {
        case productCode = "cenik"
        case quantity    = "mnozMj"
    }
}

struct NewStockMovement: Encodable {
    let description: String?
    let lines:       [NewStockMovementLine]

    enum CodingKeys: String, CodingKey {
        case documentType  = "typDokl"
        case numberSeries  = "rada"
        case movementType  = "typPohybuK"
        case warehouse     = "bsp"
        case description   = "popis"
        case lines         = "skladovePolozky"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("code:STANDARD",        forKey: .documentType)
        try c.encode("code:SKLAD-",          forKey: .numberSeries)
        try c.encode("typPohybu.vydej",      forKey: .movementType)
        try c.encode("code:SKLAD",           forKey: .warehouse)
        try c.encodeIfPresent(description,   forKey: .description)
        try c.encode(lines,                  forKey: .lines)
    }
}

struct CreateStockMovementEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let skladovyPohyb: [NewStockMovement]
        enum CodingKeys: String, CodingKey { case skladovyPohyb = "skladovy-pohyb" }
    }
}

// MARK: - Create Cash Receipt Request

struct NewCashReceipt: Encodable {
    let clientCode:  String  // raw code, e.g. "BULANAVA" — "code:" prefix added in encode
    let description: String
    let varSym:      String
    let total:       Double

    enum CodingKeys: String, CodingKey {
        case documentType = "typDokl"
        case movementType = "typPohybuK"
        case cashRegister = "pokladna"
        case clientCode   = "firma"
        case description  = "popis"
        case varSym       = "varSym"
        case noLineItems  = "bezPolozek"
        case taxExempt    = "sumOsv"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("code:STANDARD",         forKey: .documentType)
        try c.encode("typPohybu.prijem",      forKey: .movementType)
        try c.encode("code:CASH-CZK",         forKey: .cashRegister)
        try c.encode("code:\(clientCode)",    forKey: .clientCode)
        try c.encode(description,             forKey: .description)
        try c.encode(varSym,                  forKey: .varSym)
        try c.encode(true,                    forKey: .noLineItems)
        try c.encode(total,                   forKey: .taxExempt)
    }
}

struct CreateCashReceiptEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let pokladniPohyb: [NewCashReceipt]
        enum CodingKeys: String, CodingKey { case pokladniPohyb = "pokladni-pohyb" }
    }
}

// MARK: - Create Firm Request

struct NewFirm: Encodable {
    let name:  String
    let ic:    String?
    let dic:   String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case name  = "nazev"
        case ic    = "ic"
        case dic   = "dic"
        case email = "email"
        case phone = "tel"
    }
}

struct CreateFirmEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable { let adresar: [NewFirm] }
}

struct FlexiBeeCreateResult: Decodable { let id: String }
struct FlexiBeeCreateWrapper: Decodable { let results: [FlexiBeeCreateResult] }
struct FlexiBeeCreateResponse: Decodable { let winstrom: FlexiBeeCreateWrapper }

struct CashReceiptItem: Decodable { let id: String; let popis: String? }
struct CashReceiptListWrapper: Decodable {
    let items: [CashReceiptItem]
    enum CodingKeys: String, CodingKey { case items = "pokladni-pohyb" }
}
