import ComposableArchitecture
import Foundation

@DependencyClient
struct FlexiBeeClient: @unchecked Sendable {
    var loadIfNeeded: () async -> Void = {}
    var forceSync: () async -> Void = {}
    var refreshInvoicesData: () async -> Void = {}
    var stockWithPrices: () -> IdentifiedArrayOf<FlexiBeeStockWithPrice> = { [] }
    var stock: () -> [FlexiBeeStockCard] = { [] }
    var invoices: () -> [FlexiBeeInvoice] = { [] }
    var isLoading: () -> Bool = { false }
    var lastSyncDate: () -> Date? = { nil }
    var fetchFirms: () async throws -> [FlexiBeeFirm] = { [] }
    var createFirm: (_ firm: NewFirm) async throws -> FlexiBeeFirm = { _ in throw NSError() }
    var deleteFirm: (_ id: String) async throws -> Void
    var fetchLineItemsForInvoice: (_ invoiceId: String) async throws -> [FlexiBeeInvoiceItem] = { _ in [] }
    var createInvoice: (_ invoice: NewInvoice) async throws -> String = { _ in throw NSError() }
    var updateInvoice: (_ id: String, _ invoice: NewInvoice) async throws -> Void
    var deleteInvoice: (_ id: String) async throws -> Void
    var updateInvoicePaymentStatus: (_ id: String, _ status: PaymentStatus, _ method: PaymentMethod) async throws -> Void
    var fetchStockMovement: (_ invoiceId: String) async throws -> (FlexiBeeStockMovement, [FlexiBeeStockMovementItem])? = { _ in nil }
    var createStockMovement: (_ movement: NewStockMovement) async throws -> Void
    var deleteStockMovement: (_ invoiceId: String) async throws -> Void
    var fetchPDF: (_ path: String) async throws -> Data = { _ in throw NSError() }
    var fetchCashReceiptId: (_ invoiceId: String) async throws -> String? = { _ in nil }
    var createCashReceipt: (_ invoice: FlexiBeeInvoice) async throws -> Void
    var fetchSingleInvoice: (_ id: String) async throws -> FlexiBeeInvoice? = { _ in nil }
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
                isLoading: { MainActor.assumeIsolated { s.isLoading } },
                lastSyncDate: { MainActor.assumeIsolated { s.lastSyncDate } },
                fetchFirms: { try await s.fetchFirms() },
                createFirm: { firm in try await s.createFirm(firm) },
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
                fetchSingleInvoice: { id in try await s.fetchSingleInvoice(id: id) }
            )
        }
    }
}

extension DependencyValues {
    nonisolated var flexiBeeClient: FlexiBeeClient {
        get { self[FlexiBeeClient.self] }
        set { self[FlexiBeeClient.self] = newValue }
    }
}
