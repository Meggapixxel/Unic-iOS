import Foundation

/// Shared date formatter for FlexiBee API date strings (yyyy-MM-dd, POSIX locale).
private let _flexiBeeDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Price List

/// A single price-list entry from the FlexiBee `/cenik` endpoint.
struct FlexiBeeCenikItem: Identifiable, Codable {
    let id: String
    let code: String
    /// Human-readable product name; may be nil for items without a label.
    let name: String?
    /// Retail sell price including VAT.
    let sellPriceVAT: Double
    /// Wholesale purchase price (no VAT).
    let purchasePrice: Double

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code          = "kod"
        case name          = "nazev"
        case sellPriceVAT  = "cenaZaklVcDph"
        case purchasePrice = "nakupCena"
    }

    /// Comma-separated field list used in FlexiBee API requests for this type.
    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        code          = try c.decode(String.self, forKey: .code)
        name          = try c.decodeIfPresent(String.self, forKey: .name)
        sellPriceVAT  = Self.flexiDouble(c, key: .sellPriceVAT)
        purchasePrice = Self.flexiDouble(c, key: .purchasePrice)
    }

    // FlexiBee returns numeric fields as either JSON strings ("281.0") or numbers (2.34)
    private static func flexiDouble(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d }
        return 0
    }

    /// Falls back to `code` when `name` is absent.
    var displayName: String { name ?? code }
    /// Formatted sell price (no decimals), or empty when price is zero.
    var unitPrice: String   { sellPriceVAT > 0 ? String(format: "%.0f", sellPriceVAT) : "" }

}

// MARK: - Stock

/// A resolved stock card combining the price-list code, name, and current quantity.
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

/// Top-level wrapper for the `/skladova-karta` endpoint response.
struct FlexiBeeStockWrapper: Decodable {
    let cards: [FlexiBeeStockRaw]
    enum CodingKeys: String, CodingKey { case cards = "skladova-karta" }
}

/// Raw FlexiBee stock-card record; convert to `FlexiBeeStockCard` via `toCard()`.
struct FlexiBeeStockRaw: Decodable {
    private let priceListRef:        String?
    private let quantityWithDemand:  String?

    enum CodingKeys: String, CodingKey {
        case priceListRef       = "cenik@showAs"
        case quantityWithDemand = "stavMjSPozadavky"
    }

    // "cenik" is FlexiBee shorthand that expands to "cenik@showAs" in response — cannot derive from CodingKeys
    static let requestFields = "cenik,stavMjSPozadavky"

    /// Parses the `cenik@showAs` reference string and returns a typed `FlexiBeeStockCard`.
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

/// Generic FlexiBee JSON root envelope (`{ "winstrom": … }`).
struct FlexiBeeResponse<T: Decodable>: Decodable {
    let winstrom: T
}

extension FlexiBeeResponse: Sendable where T: Sendable {}

/// Winstrom body wrapper for the `/cenik` endpoint.
struct FlexiBeeCenikWrapper: Decodable {
    let cenik: [FlexiBeeCenikItem]
}

// MARK: - Joined Stock + Price

/// A view model that merges a `FlexiBeeStockCard` with its optional price-list entry.
struct FlexiBeeStockItem: Identifiable, Hashable {
    let card:  FlexiBeeStockCard
    let price: FlexiBeeCenikItem?

    var id: String { card.code }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var code:                   String  { card.code }
    var name:                   String  { card.name }
    var quantity:               Double  { card.quantity }
    var sellPriceVAT:           Double  { price?.sellPriceVAT  ?? 0 }
    var purchasePrice:          Double  { price?.purchasePrice ?? 0 }
    var formattedPurchasePrice: String  { purchasePrice.eur }

    /// The brand/product-line prefix extracted from the full name (e.g. "Wella" from "Wella - Color - 60ml").
    var productLine: String {
        guard let range = name.range(of: " - ") else { return "—" }
        return String(name[name.startIndex..<range.lowerBound])
    }

    /// Volume or size segment from the last " - " component of the name, when available.
    var volume: String? {
        let parts = name.components(separatedBy: " - ")
        guard parts.count >= 3 else { return nil }
        return parts.last
    }

    /// Product name with the product-line prefix and volume suffix stripped.
    var productName: String { _parsedProductName(name) }
}

/// Strips the leading product-line and trailing volume from a raw FlexiBee product name.
/// - Parameter raw: The full product name string.
/// - Returns: The middle segment(s) joined by " - ".
private func _parsedProductName(_ raw: String) -> String {
    let parts = raw.components(separatedBy: " - ")
    guard parts.count >= 2 else { return raw }
    let withoutLine = parts.dropFirst()
    return (parts.count >= 3 ? withoutLine.dropLast() : withoutLine).joined(separator: " - ")
}

/// Decoded FlexiBee error payload; used to extract a human-readable message from failed responses.
struct FlexiBeeErrorResponse: Decodable {
    let winstrom: Winstrom

    /// Inner container holding the status and any error details.
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

/// Invoice payment state derived from the FlexiBee `stavUhrK` field.
enum PaymentStatus: String, CaseIterable {
    case paid    = "uhrazeno"
    case partial = "castecneUhrazeno"
    case unpaid  = "neuhrazeno"
    case overdue

    /// Localised display label shown in the UI.
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

/// An issued invoice (`faktura-vydana`) fetched from FlexiBee.
struct FlexiBeeInvoice: Identifiable, Codable, Hashable {
    let id:                String
    let code:              String?
    let notes:             String?
    let finalText:         String?
    let clientIc:          String?
    let clientDic:         String?
    let isAccounted:       Bool?
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
        case clientIc          = "ic"
        case clientDic         = "dic"
        case isAccounted       = "zuctovano"
        case issueDateRaw      = "datVyst"
        case dueDateRaw        = "datSplat"
        case totalRaw          = "sumCelkem"
        case paymentStatusCode = "stavUhrK"
        case clientRef         = "firma@showAs"
        case paymentMethodCode = "formaUhradyCis"
        case varSym            = "varSym"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(String.self,  forKey: .id)
        code              = try c.decodeIfPresent(String.self,  forKey: .code)
        notes             = try c.decodeIfPresent(String.self,  forKey: .notes)
        finalText         = try c.decodeIfPresent(String.self,  forKey: .finalText)
        clientIc          = try c.decodeIfPresent(String.self,  forKey: .clientIc)
        clientDic         = try c.decodeIfPresent(String.self,  forKey: .clientDic)
        issueDateRaw      = try c.decodeIfPresent(String.self,  forKey: .issueDateRaw)
        dueDateRaw        = try c.decodeIfPresent(String.self,  forKey: .dueDateRaw)
        totalRaw          = try c.decodeIfPresent(String.self,  forKey: .totalRaw)
        paymentStatusCode = try c.decodeIfPresent(String.self,  forKey: .paymentStatusCode)
        clientRef         = try c.decodeIfPresent(String.self,  forKey: .clientRef)
        paymentMethodCode = try c.decodeIfPresent(String.self,  forKey: .paymentMethodCode)
        varSym            = try c.decodeIfPresent(String.self,  forKey: .varSym)
        // FlexiBee returns booleans as strings ("true"/"false")
        if let boolVal = try? c.decode(Bool.self, forKey: .isAccounted) {
            isAccounted = boolVal
        } else if let strVal = try? c.decode(String.self, forKey: .isAccounted) {
            isAccounted = strVal == "true"
        } else {
            isAccounted = nil
        }
    }

    /// Comma-separated field list used in FlexiBee API requests for this type.
    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    /// Total invoice amount (sum including VAT).
    var total:         Double  { Double(totalRaw ?? "") ?? 0 }
    /// Parsed issue date from the raw string.
    var issueDate:     Date?   { Self.parseDate(issueDateRaw) }
    /// Parsed payment due date from the raw string.
    var dueDate:       Date?   { Self.parseDate(dueDateRaw) }
    /// Human-readable invoice identifier; prefers the formatted `code` over the raw `id`.
    var invoiceNumber: String  { code ?? id }

    /// Full client name extracted from the `firma@showAs` reference (e.g. "CODE: Name").
    var clientName: String {
        guard let raw = clientRef, let range = raw.range(of: ": ") else { return clientRef ?? "—" }
        return String(raw[range.upperBound...])
    }

    /// Short code of the client address-book entry, or nil when unavailable.
    var clientCode: String? {
        guard let raw = clientRef, let range = raw.range(of: ": ") else { return nil }
        return String(raw[raw.startIndex..<range.lowerBound])
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }

    /// Typed payment method derived from the raw FlexiBee code.
    var paymentMethod: PaymentMethod? { PaymentMethod(rawValue: paymentMethodCode ?? "") }

    /// Computed payment status; falls back to `.overdue` when unpaid past the due date.
    var paymentStatus: PaymentStatus {
        let s = paymentStatusCode ?? ""
        if s.contains("castecne") { return .partial }
        if s.contains("uhrazeno") { return .paid }
        if let due = dueDate, due < Date() { return .overdue }
        return .unpaid
    }
}

/// Winstrom body wrapper for the `/faktura-vydana` endpoint.
struct FlexiBeeInvoicesWrapper: Decodable {
    let invoices: [FlexiBeeInvoice]
    enum CodingKeys: String, CodingKey { case invoices = "faktura-vydana" }
}

// MARK: - Invoice Line Item

/// A single line item (`faktura-vydana-polozka`) belonging to an issued invoice.
struct FlexiBeeInvoiceItem: Identifiable, Codable, Equatable {
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

    /// Comma-separated field list used in FlexiBee API requests for this type.
    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    /// Ordered quantity on this line.
    var quantity:    Double  { Double(quantityRaw ?? "") ?? 0 }
    /// Line total (VAT included).
    var total:       Double  { Double(totalRaw    ?? "") ?? 0 }
    /// Price-list article code for this line.
    var productCode: String  { codeRaw ?? "" }
    /// Parsed product name with brand prefix and volume stripped.
    var productName: String  { _parsedProductName(nameRaw ?? codeRaw ?? "—") }
    /// Returns `true` when the line has both a code and a positive quantity.
    var isValid:     Bool    { !productCode.isEmpty && quantity > 0 }

    // Canonical price list code (CFB/220), used for stock matching
    /// Canonical price-list code (`CFB/220` form), stripping the `code:` prefix if present.
    var cenikCode: String {
        guard let ref = cenikRef else { return productCode }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    /// Non-nil only when the item has an explicit ceník reference (real stock item, not a bundle).
    var stockCode: String? {
        guard let ref = cenikRef, !ref.isEmpty else { return nil }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    var date: Date? {
        guard let s = issueDateRaw else { return nil }
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }
}

/// Winstrom body wrapper for the `/faktura-vydana-polozka` endpoint.
struct FlexiBeeInvoiceItemsWrapper: Decodable {
    let items: [FlexiBeeInvoiceItem]
    enum CodingKeys: String, CodingKey { case items = "faktura-vydana-polozka" }
}

// MARK: - Stock Movement (Warehouse outflow header)

/// Header record for a warehouse outflow document (`skladovy-pohyb`).
struct FlexiBeeStockMovement: Decodable, Sendable {
    let id:    String
    let code:  String
    let notes: String?
    enum CodingKeys: String, CodingKey { case id; case code = "kod"; case notes = "popis" }
}

/// Winstrom body wrapper for the `/skladovy-pohyb` endpoint.
struct FlexiBeeStockMovementWrapper: Decodable, Sendable {
    let movements: [FlexiBeeStockMovement]
    enum CodingKeys: String, CodingKey { case movements = "skladovy-pohyb" }
}

// MARK: - Stock Movement Item (Warehouse outflow line)

/// A single line item (`skladovy-pohyb-polozka`) of a warehouse outflow document.
struct FlexiBeeStockMovementItem: Identifiable, Codable, Equatable, Sendable {
    let id:              String
    private let codeRaw:         String?
    private let nameRaw:         String?
    private let dateRaw:         String?
    private let quantityRaw:     String?
    private let totalRaw:        String?
    private let cenikRef:        String?  // "code:CFB/220" — canonical price-list code
    let movementCodeRef:         String?  // "code:S-0001/2026" — parent movement (doklSklad, requires detail=full)

    enum CodingKeys: String, CodingKey {
        case id
        case codeRaw         = "kod"
        case nameRaw         = "nazev"
        case dateRaw         = "datVyst"
        case quantityRaw     = "mnozMj"
        case totalRaw        = "sumCelkem"
        case cenikRef        = "cenik"
        case movementCodeRef = "doklSklad"
    }

    static let apiFields    = "id,kod,nazev,datVyst,mnozMj,sumCelkem,cenik"
    static let bulkApiFields = apiFields + ",doklSklad"

    /// The human-readable movement document code (e.g. "S-0001/2026"), stripped of `code:` prefix.
    var movementCode: String? {
        guard let ref = movementCodeRef, ref.hasPrefix("code:") else { return nil }
        return String(ref.dropFirst(5))
    }

    /// Article code of the product issued.
    var productCode:    String { codeRaw ?? "" }
    /// Parsed product name with brand prefix and volume stripped.
    var productName:    String { _parsedProductName(nameRaw ?? codeRaw ?? "—") }
    /// Number of units issued from stock.
    var quantityIssued: Double { Double(quantityRaw ?? "") ?? 0 }
    /// Line total value (purchase price × quantity).
    var total:          Double { Double(totalRaw ?? "") ?? 0 }

    /// Canonical price-list code, stripping `code:` prefix if present.
    var cenikCode: String {
        guard let ref = cenikRef else { return productCode }
        return ref.hasPrefix("code:") ? String(ref.dropFirst(5)) : ref
    }

    var date: Date? {
        guard let s = dateRaw else { return nil }
        return _flexiBeeDateFormatter.date(from: String(s.prefix(10)))
    }

    /// Returns `true` when the line has a code and a positive issued quantity.
    var isValid: Bool { !productCode.isEmpty && quantityIssued > 0 }
}

/// Winstrom body wrapper for the `/skladovy-pohyb-polozka` endpoint.
struct FlexiBeeStockMovementItemsWrapper: Decodable, Sendable {
    let items: [FlexiBeeStockMovementItem]
    enum CodingKeys: String, CodingKey { case items = "skladovy-pohyb-polozka" }
}

// MARK: - Payment Method

/// Available payment methods mapped to FlexiBee `formaUhradyCis` codes.
enum PaymentMethod: String, CaseIterable {
    case prevod = "code:PREVOD"
    case hotove = "code:HOTOVE"
    case karta  = "code:KARTA"

    /// Localised display name for the payment method.
    var displayName: String {
        switch self {
        case .prevod: return String.payment_method_prevod
        case .hotove: return String.payment_method_hotove
        case .karta:  return String.payment_method_karta
        }
    }

    /// SF Symbol name representing this payment method.
    var icon: String {
        switch self {
        case .prevod: return "building.columns"
        case .hotove: return "banknote"
        case .karta:  return "creditcard"
        }
    }
}

// MARK: - Firm (Client / Address Book)

/// A FlexiBee address-book entry (`adresar`) representing a client or partner.
struct FlexiBeeFirm: Identifiable, Decodable, Equatable {
    let id:    String
    let code:  String
    let name:  String?
    let ic:    String?
    let dic:   String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case code  = "kod"
        case name  = "nazev"
        case ic    = "ic"
        case dic   = "dic"
        case email = "email"
        case phone = "tel"
    }

    static var apiFields: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    /// Falls back to `code` when `name` is nil or empty.
    var displayName: String {
        let n = name ?? ""
        return n.isEmpty ? code : n
    }
}

/// Winstrom body wrapper for the `/adresar` endpoint.
struct FlexiBeeFirmWrapper: Decodable {
    let firms: [FlexiBeeFirm]
    enum CodingKeys: String, CodingKey { case firms = "adresar" }
}

// MARK: - Create Invoice Request

/// A single line item used when creating or updating an invoice in FlexiBee.
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

    /// Creates a new invoice line.
    /// - Parameters:
    ///   - name: Display name of the product or service.
    ///   - productCode: Optional FlexiBee price-list code; when supplied the line links to stock.
    ///   - quantity: Number of units.
    ///   - unitPrice: Price per unit (VAT inclusive).
    ///   - vatRate: VAT rate in percent (default 21 %).
    init(name: String, productCode: String? = nil, quantity: Double, unitPrice: Double, vatRate: Double = 21.0) {
        self.name        = name
        self.productCode = productCode
        self.quantity    = quantity
        self.unitPrice   = unitPrice
        self.vatRate     = vatRate
        self.priceType   = "typCeny.sDph"
    }
}

/// The full payload sent to FlexiBee when creating or replacing an issued invoice.
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

/// Top-level `winstrom` envelope that wraps a `NewInvoice` for the create/update POST body.
struct CreateInvoiceEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let fakturaVydana: [NewInvoice]
        enum CodingKeys: String, CodingKey { case fakturaVydana = "faktura-vydana" }
    }
}

// MARK: - Create Stock Movement Request

/// A single product line in a new warehouse outflow document.
struct NewStockMovementLine: Encodable {
    let productCode: String
    let quantity:    Double

    enum CodingKeys: String, CodingKey {
        case productCode = "cenik"
        case quantity    = "mnozMj"
    }
}

/// Payload for creating a STANDARD warehouse outflow movement (`skladovy-pohyb`).
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

/// Top-level `winstrom` envelope wrapping a `NewStockMovement` for the POST body.
struct CreateStockMovementEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let skladovyPohyb: [NewStockMovement]
        enum CodingKeys: String, CodingKey { case skladovyPohyb = "skladovy-pohyb" }
    }
}

// MARK: - Create Cash Receipt Request

/// Payload for creating a cash receipt (`pokladni-pohyb`) linked to a paid invoice.
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

/// Top-level `winstrom` envelope wrapping a `NewCashReceipt` for the POST body.
struct CreateCashReceiptEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable {
        let pokladniPohyb: [NewCashReceipt]
        enum CodingKeys: String, CodingKey { case pokladniPohyb = "pokladni-pohyb" }
    }
}

// MARK: - Create Firm Request

/// Payload for creating or updating a client (`adresar`) in FlexiBee.
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

/// Top-level `winstrom` envelope wrapping a `NewFirm` for the POST/PUT body.
struct CreateFirmEnvelope: Encodable {
    let winstrom: Winstrom
    struct Winstrom: Encodable { let adresar: [NewFirm] }
}

/// Single result entry returned by FlexiBee after a successful create operation.
struct FlexiBeeCreateResult: Decodable { let id: String }
/// Winstrom payload wrapping a list of create results.
struct FlexiBeeCreateWrapper: Decodable { let results: [FlexiBeeCreateResult] }
/// Top-level response for FlexiBee create operations, containing the new record IDs.
struct FlexiBeeCreateResponse: Decodable { let winstrom: FlexiBeeCreateWrapper }

/// Lightweight cash-receipt record used only for building the receipt-ID lookup cache.
struct CashReceiptItem: Decodable { let id: String; let popis: String? }
/// Winstrom body wrapper for the `/pokladni-pohyb` list endpoint.
struct CashReceiptListWrapper: Decodable {
    let items: [CashReceiptItem]
    enum CodingKeys: String, CodingKey { case items = "pokladni-pohyb" }
}
