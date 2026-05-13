import ComposableArchitecture
import Foundation

@DependencyClient
struct FlexiBeeClient {
    var loadIfNeeded: () async -> Void = {}
    var forceSync: () async -> Void = {}
    var refreshInvoicesData: () async -> Void = {}
    var stockWithPrices: () -> IdentifiedArrayOf<FlexiBeeStockWithPrice> = { [] }
    var stock: () -> [FlexiBeeStockCard] = { [] }
    var invoices: () -> [FlexiBeeInvoice] = { [] }
    var isLoading: () -> Bool = { false }
    var lastSyncDate: () -> Date? = { nil }
    var fetchFirms: () async throws -> [FlexiBeeFirm] = { [] }
    var createFirm: (_ firm: FlexiBeeFirm) async throws -> FlexiBeeFirm = { _ in throw NSError() }
    var deleteFirm: (_ id: String) async throws -> Void
    var fetchLineItemsForInvoice: (_ invoice: FlexiBeeInvoice) async throws -> [FlexiBeeInvoiceItem] = { _ in [] }
    var createInvoice: (_ invoice: FlexiBeeInvoice) async throws -> String = { _ in throw NSError() }
    var updateInvoice: (_ id: String, _ invoice: FlexiBeeInvoice) async throws -> Void
    var deleteInvoice: (_ id: String) async throws -> Void
    var updateInvoicePaymentStatus: (_ id: String, _ status: PaymentStatus, _ method: PaymentMethod?) async throws -> Void
    var fetchStockMovement: (_ invoiceId: String) async throws -> (FlexiBeeStockMovement, [FlexiBeeStockMovementItem])? = { _ in nil }
    var createStockMovement: (_ movement: FlexiBeeStockMovement) async throws -> Void
    var deleteStockMovement: (_ invoiceId: String) async throws -> Void
    var fetchPDF: (_ path: String) async throws -> Data = { _ in throw NSError() }
    var fetchCashReceiptId: (_ invoiceId: String) async throws -> String? = { _ in nil }
    var createCashReceipt: (_ invoiceId: String) async throws -> Void
    var fetchSingleInvoice: (_ id: String) async throws -> FlexiBeeInvoice = { _ in throw NSError() }
}

extension FlexiBeeClient: DependencyKey {
    static var liveValue: Self {
        let s = FlexiBeeService.shared
        return Self(
            loadIfNeeded: { await s.loadIfNeeded() },
            forceSync: { await s.forceSync() },
            refreshInvoicesData: { await s.refreshInvoicesData() },
            stockWithPrices: { s.stockWithPrices },
            stock: { s.stock },
            invoices: { s.invoices },
            isLoading: { s.isLoading },
            lastSyncDate: { s.lastSyncDate },
            fetchFirms: { try await s.fetchFirms() },
            createFirm: { firm in try await s.createFirm(firm) },
            deleteFirm: { id in try await s.deleteFirm(id: id) },
            fetchLineItemsForInvoice: { invoice in try await s.fetchLineItemsForInvoice(invoice) },
            createInvoice: { invoice in try await s.createInvoice(invoice) },
            updateInvoice: { id, invoice in try await s.updateInvoice(id: id, invoice: invoice) },
            deleteInvoice: { id in try await s.deleteInvoice(id: id) },
            updateInvoicePaymentStatus: { id, status, method in try await s.updateInvoicePaymentStatus(id: id, status: status, method: method) },
            fetchStockMovement: { id in try await s.fetchStockMovement(for: id) },
            createStockMovement: { movement in try await s.createStockMovement(movement) },
            deleteStockMovement: { id in try await s.deleteStockMovement(for: id) },
            fetchPDF: { path in try await s.fetchPDF(path: path) },
            fetchCashReceiptId: { id in try await s.fetchCashReceiptId(for: id) },
            createCashReceipt: { id in try await s.createCashReceipt(for: id) },
            fetchSingleInvoice: { id in try await s.fetchSingleInvoice(id: id) }
        )
    }
}

extension DependencyValues {
    var flexiBeeClient: FlexiBeeClient {
        get { self[FlexiBeeClient.self] }
        set { self[FlexiBeeClient.self] = newValue }
    }
}
