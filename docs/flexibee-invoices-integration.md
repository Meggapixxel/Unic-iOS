# FlexiBee — Інтеграція фактур (майбутня)

## Статус
Не реалізовано. Код моделей і сервісу прибраний навмисно — ця документація описує що і як треба зробити.

## Що треба додати

### 1. Відновити моделі у `FlexiBeeModels.swift`

```swift
// MARK: - Invoice

struct FlexiBeeInvoice: Identifiable, Decodable {
    let id: String?
    let kod: String?
    let firmaShowAs: String?
    private let sumCelkem: String?
    let stavUhrK: String?
    let datVyst: String?
    let datSplat: String?
    let mena: String?

    enum CodingKeys: String, CodingKey {
        case id, kod, sumCelkem, stavUhrK, datVyst, datSplat, mena
        case firmaShowAs = "firma@showAs"
    }

    var total: Double { Double(sumCelkem ?? "") ?? 0 }
    var currency: String { mena ?? "CZK" }
    var invoiceNumber: String { kod ?? "—" }

    var companyName: String {
        guard let showAs = firmaShowAs else { return "—" }
        if let range = showAs.range(of: ": ") { return String(showAs[range.upperBound...]) }
        return showAs
    }

    var paymentStatus: InvoicePaymentStatus {
        guard let s = stavUhrK else { return .unpaid }
        if s.contains("uhrazenoRucne") || s == "stavUhr.uhrazeno" { return .paid }
        if s.contains("castecne") { return .partial }
        return .unpaid
    }

    var issuedDate: Date? { Self.parseDate(datVyst) }
    var dueDate: Date?   { Self.parseDate(datSplat) }
    var isOverdue: Bool  { paymentStatus == .unpaid && (dueDate ?? .distantFuture) < Date() }

    private static func parseDate(_ str: String?) -> Date? {
        guard let s = str else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(s.prefix(10)))
    }
}

enum InvoicePaymentStatus: Equatable {
    case paid, partial, unpaid

    var label: String {
        switch self {
        case .paid:    return "Оплачено"
        case .partial: return "Частково"
        case .unpaid:  return "Не оплачено"
        }
    }

    var color: Color {
        switch self {
        case .paid:    return .green
        case .partial: return .orange
        case .unpaid:  return .red
        }
    }

    var icon: String {
        switch self {
        case .paid:    return "checkmark.circle.fill"
        case .partial: return "clock.circle.fill"
        case .unpaid:  return "exclamationmark.circle.fill"
        }
    }
}

// Response wrappers
struct FlexiBeeIssuedWrapper: Decodable {
    let invoices: [FlexiBeeInvoice]
    enum CodingKeys: String, CodingKey { case invoices = "faktura-vydana" }
}

struct FlexiBeeReceivedWrapper: Decodable {
    let invoices: [FlexiBeeInvoice]
    enum CodingKeys: String, CodingKey { case invoices = "faktura-prijata" }
}
```

---

### 2. Відновити методи у `FlexiBeeService.swift`

```swift
func fetchIssuedInvoices() async throws -> [FlexiBeeInvoice] {
    let response = try await fetch(
        FlexiBeeResponse<FlexiBeeIssuedWrapper>.self,
        path: "/faktura-vydana.json",
        fields: "id,kod,firma,sumCelkem,stavUhrK,datVyst,datSplat,mena",
        limit: 200
    )
    return response.winstrom.invoices
}

func fetchReceivedInvoices() async throws -> [FlexiBeeInvoice] {
    let response = try await fetch(
        FlexiBeeResponse<FlexiBeeReceivedWrapper>.self,
        path: "/faktura-prijata.json",
        fields: "id,kod,firma,sumCelkem,stavUhrK,datVyst,datSplat,mena",
        limit: 200
    )
    return response.winstrom.invoices
}
```

**Важливо:** `firma` в `fields` — без `(nazev)`. FlexiBee автоматично додає `firma@showAs` як метадані до reference-поля. Саме з нього парситься назва компанії.

---

### 3. Додати в `FlexiBeeViewModel.swift`

У клас:
```swift
@Published var issuedInvoices: [FlexiBeeInvoice] = []
@Published var receivedInvoices: [FlexiBeeInvoice] = []
@Published var invoiceFilter: InvoicePaymentStatus? = nil
```

Computed properties:
```swift
var filteredIssuedInvoices: [FlexiBeeInvoice] { applyInvoiceFilters(issuedInvoices) }
var filteredReceivedInvoices: [FlexiBeeInvoice] { applyInvoiceFilters(receivedInvoices) }

private func applyInvoiceFilters(_ invoices: [FlexiBeeInvoice]) -> [FlexiBeeInvoice] {
    var result = invoices
    if let filter = invoiceFilter { result = result.filter { $0.paymentStatus == filter } }
    if !searchText.isEmpty {
        let q = searchText.lowercased()
        result = result.filter {
            $0.invoiceNumber.lowercased().contains(q) || $0.companyName.lowercased().contains(q)
        }
    }
    return result.sorted { ($0.issuedDate ?? .distantPast) > ($1.issuedDate ?? .distantPast) }
}

var unpaidIssuedCount: Int { issuedInvoices.filter { $0.paymentStatus == .unpaid }.count }
var unpaidReceivedCount: Int { receivedInvoices.filter { $0.paymentStatus == .unpaid }.count }
var totalIssuedPaidRevenue: Double {
    issuedInvoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total }
}
```

У `fetchAll()` додати паралельне завантаження:
```swift
async let issuedTask = service.fetchIssuedInvoices()
async let receivedTask = service.fetchReceivedInvoices()
// ...
if let i = try? await issuedTask { issuedInvoices = i } else { errors.append("видані фактури") }
if let r = try? await receivedTask { receivedInvoices = r } else { errors.append("прийняті фактури") }
```

Також додати `.issued` і `.received` в `FlexiBeeSection` і `resetFilters()`.

---

### 4. Відновити UI у `FlexiBeeView.swift`

Секцію пікера — додати `.issued` / `.received` кейси.

View для рядка фактури (готовий код):
```swift
private struct InvoiceRow: View {
    let invoice: FlexiBeeInvoice

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.invoiceNumber).font(.headline)
                Text(invoice.companyName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let date = invoice.issuedDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAmount(invoice.total, currency: invoice.currency)).font(.subheadline.bold())
                HStack(spacing: 3) {
                    Image(systemName: invoice.isOverdue ? "clock.badge.exclamationmark" : invoice.paymentStatus.icon)
                        .font(.caption)
                    Text(invoice.isOverdue ? "Прострочено" : invoice.paymentStatus.label).font(.caption)
                }
                .foregroundStyle(invoice.isOverdue ? .red : invoice.paymentStatus.color)
            }
        }
        .padding(.vertical, 2)
    }
}
```

---

## API ендпоінти

| Ресурс | URL | Поля |
|--------|-----|------|
| Видані фактури | `GET /faktura-vydana.json` | `id,kod,firma,sumCelkem,stavUhrK,datVyst,datSplat,mena` |
| Прийняті фактури | `GET /faktura-prijata.json` | `id,kod,firma,sumCelkem,stavUhrK,datVyst,datSplat,mena` |

## Значення `stavUhrK`

| Значення | Сенс |
|----------|------|
| `stavUhr.uhrazenoRucne` | Оплачено вручну |
| `stavUhr.uhrazeno` | Оплачено через банк |
| `stavUhr.castecneUhrazeno` | Частково оплачено |
| `stavUhr.neuhrazeno` | Не оплачено |

## Типи фактур (`typDokl`)

| Код | Назва | Коли |
|-----|-------|------|
| `FAKTURA` | Стандартна фактура | Всі рахунки від UNIC PRO та клієнтам |
| `ZÁLOHA` | Авансовий рахунок | Передоплата, напр. ліцензія ABRA |
| `ZDD` | Zálohový daňový doklad | Видає постачальник після отримання zálohy — чекати на email |
