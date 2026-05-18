import ComposableArchitecture
import Foundation

/// TCA dependency that exposes `FlexiBeeService` functionality to reducers via `@Dependency`.
/// All closures are fulfilled by the live value through `FlexiBeeService.shared`.
@DependencyClient
struct FlexiBeeClient: @unchecked Sendable {
    /// Fetches all data when the cache is stale; no-op when valid.
    var loadIfNeeded: () async -> Void = {}
    /// Unconditionally re-fetches all data, bypassing the cache.
    var forceSync: () async -> Void = {}
    /// Lightweight refresh that only reloads invoices, line items, and receipts.
    var refreshInvoicesData: () async -> Void = {}
    /// Returns the current joined stock+price array from the in-memory cache.
    var stockWithPrices: () -> IdentifiedArrayOf<FlexiBeeStockItem> = { [] }
    /// Returns the current stock cards from the in-memory cache.
    var stock: () -> [FlexiBeeStockCard] = { [] }
    /// Returns the current invoices list from the in-memory cache.
    var invoices: () -> [FlexiBeeInvoice] = { [] }
    /// Returns the current sales movement items from the in-memory cache.
    var salesMovementItems: () -> [FlexiBeeStockMovementItem] = { [] }
    /// Returns `true` while a network sync is in progress.
    var isLoading: () -> Bool = { false }
    /// Returns the timestamp of the last successful sync.
    var lastSyncDate: () -> Date? = { nil }
    /// Fetches all address-book entries sorted by display name.
    var fetchFirms: () async throws -> [FlexiBeeFirm] = { [] }
    /// Fetches a single address-book entry by short code.
    var fetchFirm: (_ code: String) async throws -> FlexiBeeFirm? = { _ in nil }
    /// Creates a new address-book entry and returns the populated record.
    var createFirm: (_ firm: NewFirm) async throws -> FlexiBeeFirm = { _ in throw NSError() }
    /// Updates an existing address-book entry identified by `code`.
    var updateFirm: (_ code: String, _ firm: NewFirm) async throws -> Void
    /// Permanently deletes an address-book entry by its internal ID.
    var deleteFirm: (_ id: String) async throws -> Void
    /// Fetches line items for a specific invoice, using an in-memory cache.
    var fetchLineItemsForInvoice: (_ invoiceId: String) async throws -> [FlexiBeeInvoiceItem] = { _ in [] }
    /// Creates a new issued invoice and returns its internal ID.
    var createInvoice: (_ invoice: NewInvoice) async throws -> String = { _ in throw NSError() }
    /// Replaces all fields and line items of an existing invoice.
    var updateInvoice: (_ id: String, _ invoice: NewInvoice) async throws -> Void
    /// Permanently deletes an issued invoice.
    var deleteInvoice: (_ id: String) async throws -> Void
    /// Marks an invoice as manually paid with the given payment method.
    var updateInvoicePaymentStatus: (_ id: String, _ status: PaymentStatus, _ method: PaymentMethod) async throws -> Void
    /// Returns the warehouse outflow movement and its items linked to a given invoice, or `nil`.
    var fetchStockMovement: (_ invoiceId: String) async throws -> (FlexiBeeStockMovement, [FlexiBeeStockMovementItem])? = { _ in nil }
    /// Creates a STANDARD warehouse outflow movement.
    var createStockMovement: (_ movement: NewStockMovement) async throws -> Void
    /// Deletes (or stornos) the outflow movement linked to the given invoice number.
    var deleteStockMovement: (_ invoiceId: String) async throws -> Void
    /// Downloads a PDF document from FlexiBee by its relative path.
    var fetchPDF: (_ path: String) async throws -> Data = { _ in throw NSError() }
    /// Returns the FlexiBee ID of the cash receipt linked to the given invoice number.
    var fetchCashReceiptId: (_ invoiceId: String) async throws -> String? = { _ in nil }
    /// Creates a cash receipt for a paid invoice.
    var createCashReceipt: (_ invoice: FlexiBeeInvoice) async throws -> Void
    /// Fetches a single invoice by its internal ID with full detail.
    var fetchSingleInvoice: (_ id: String) async throws -> FlexiBeeInvoice? = { _ in nil }
    /// Flags an invoice as accounted in FlexiBee.
    var markAsAccounted: (_ id: String) async throws -> Void
}

extension FlexiBeeClient: DependencyKey {
    static var liveValue: Self {
        MainActor.assumeIsolated {
            let s = FlexiBeeService.shared
            return Self(
                loadIfNeeded: { await s.loadIfNeeded() },
                forceSync: { await s.forceSync() },
                refreshInvoicesData: { await s.refreshInvoicesData() },
                stockWithPrices: { MainActor.assumeIsolated { s.stockWithPrices } },
                stock: { MainActor.assumeIsolated { s.stock } },
                invoices: { MainActor.assumeIsolated { s.invoices } },
                salesMovementItems: { MainActor.assumeIsolated { s.salesMovementItems } },
                isLoading: { MainActor.assumeIsolated { s.isLoading } },
                lastSyncDate: { MainActor.assumeIsolated { s.lastSyncDate } },
                fetchFirms: { try await s.fetchFirms() },
                fetchFirm: { code in try await s.fetchFirm(code: code) },
                createFirm: { firm in try await s.createFirm(firm) },
                updateFirm: { code, firm in try await s.updateFirm(code: code, firm: firm) },
                deleteFirm: { id in try await s.deleteFirm(id: id) },
                fetchLineItemsForInvoice: { invoiceId in try await s.fetchLineItemsForInvoice(invoiceId) },
                createInvoice: { invoice in try await s.createInvoice(invoice) },
                updateInvoice: { id, invoice in try await s.updateInvoice(id: id, invoice: invoice) },
                deleteInvoice: { id in try await s.deleteInvoice(id: id) },
                updateInvoicePaymentStatus: { id, status, method in try await s.updateInvoicePaymentStatus(id: id, status: status, method: method) },
                fetchStockMovement: { id in try await s.fetchStockMovement(for: id) },
                createStockMovement: { movement in try await s.createStockMovement(movement) },
                deleteStockMovement: { id in try await s.deleteStockMovement(for: id) },
                fetchPDF: { path in try await s.fetchPDF(path: path) },
                fetchCashReceiptId: { id in try await s.fetchCashReceiptId(for: id) },
                createCashReceipt: { invoice in try await s.createCashReceipt(for: invoice) },
                fetchSingleInvoice: { id in try await s.fetchSingleInvoice(id: id) },
                markAsAccounted: { id in try await s.markAsAccounted(id: id) }
            )
        }
    }
}

extension DependencyValues {
    /// The `FlexiBeeClient` dependency for use with `@Dependency(\.flexiBeeClient)`.
    nonisolated var flexiBeeClient: FlexiBeeClient {
        get { self[FlexiBeeClient.self] }
        set { self[FlexiBeeClient.self] = newValue }
    }
}
