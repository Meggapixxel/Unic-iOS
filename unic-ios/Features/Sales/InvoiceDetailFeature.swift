// FILE: unic-ios/Features/Sales/InvoiceDetailFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - InvoiceDetailFeature

/// Manages the full lifecycle of a single FlexiBee invoice detail screen, covering line-item
/// display, payment-status mutation, cash-receipt creation, stock-movement linkage, PDF sharing,
/// accounting mark, and invoice deletion.
///
/// ## Entry point
/// `onLoad` is dispatched when `InvoiceDetailView` appears. It fetches three resources in
/// parallel from FlexiBee: the filtered line items for the invoice, the linked stock movement
/// (if any), and the cash-receipt document ID (if any). Results are delivered via `loaded`.
///
/// ## Key action flows
///
/// - **`onLoad`** — Sets `isLoading = true`, then concurrently fetches line items
///   (`fetchLineItemsForInvoice`), the stock movement (`fetchStockMovement`), and the cash
///   receipt ID (`fetchCashReceiptId`). On success dispatches `loaded`; on failure dispatches
///   `failed`.
///
/// - **`editTapped`** — Presents `.editForm(InvoiceFormPlaceholderFeature)` carrying the
///   current invoice. Only reachable when `canEdit == true` (invoice is not paid).
///   On `.submitted`, refreshes the invoice via `fetchSingleInvoice` then re-runs `onLoad`
///   to reload line items. On `.dismiss`, simply closes the sheet.
///
/// - **`deleteTapped`** — Presents `.deleteAlert(ConfirmationDialogFeature)`.
///   On `.confirmed` dispatches `deleteConfirmed`, which sequentially calls
///   `deleteStockMovement` (to unlink the warehouse record) then `deleteInvoice`.
///   On success dispatches `deleteCompleted` (parent pops the screen); on failure dispatches
///   `failed`.
///
/// - **`setPaymentStatus(_:_:)`** — Presents `.statusChange(StatusChangeFeature)` pre-loaded
///   with the target status and payment method. On `.confirmed`, dispatches
///   `statusChangeConfirmed` which calls `createCashReceipt` (when paying by cash) and
///   `updateInvoicePaymentStatus`, then re-fetches the invoice via `fetchSingleInvoice` to
///   update local state.
///
/// - **`accountingTapped`** — Calls `markAsAccounted`, then re-fetches the invoice so that
///   `isAccounted` reflects the updated value without requiring a full reload.
///
/// - **`openStockMovement`** — Presents `.stockMovement(StockMovementPlaceholderFeature)`
///   seeded with the invoice ID, number, and current line items. On `.submitted`, re-runs
///   `onLoad` to pick up the newly created movement record.
///
/// - **`shareInvoicePDF`** — Fetches the invoice PDF from
///   `/faktura-vydana/<id>.pdf` via `flexiBeeClient.fetchPDF`, then dispatches `pdfLoaded`
///   to surface the share sheet.
///
/// - **`shareCashReceiptPDF`** — Fetches `/pokladni-pohyb/<receiptId>.pdf`. Requires
///   `cashReceiptId` to be non-nil.
///
/// - **`shareBothPDFs`** — Fetches the invoice and cash-receipt PDFs concurrently using
///   `async let`, then bundles them into a single `PDFShareItem` with two files. Falls back
///   to `shareInvoicePDF` if no receipt ID is available.
///
/// - **`pdfShareDismissed`** — Clears `pdfShareItem` after the system share sheet closes.
///
/// - **`productTapped`, `clientTapped`** — No-op within this reducer; navigation is handled
///   by the parent feature via action bubbling.
///
/// ## Navigation (Destination)
/// All presentations are single-slot `@Presents var destination: Destination.State?`:
/// - `.editForm` — Invoice edit sheet (`InvoiceFormPlaceholderFeature`).
/// - `.stockMovement` — Stock-movement creation sheet (`StockMovementPlaceholderFeature`).
/// - `.statusChange` — Payment-method picker sheet (`StatusChangeFeature`).
/// - `.deleteAlert` — Destructive-action confirmation alert (`ConfirmationDialogFeature`).
///
/// ## Side effects
/// - `fetchLineItemsForInvoice` / `fetchStockMovement` / `fetchCashReceiptId` — parallel reads
///   on `onLoad`.
/// - `fetchSingleInvoice` — re-fetches the invoice after an edit submission or status change.
/// - `updateInvoicePaymentStatus` — mutates payment status in FlexiBee.
/// - `createCashReceipt` — creates a cash-register entry when paying by cash (hotove).
/// - `markAsAccounted` — posts the accounting flag to FlexiBee.
/// - `deleteStockMovement` + `deleteInvoice` — sequential destructive calls on delete confirm.
/// - `fetchPDF` — downloads binary PDF data for the invoice or cash receipt.
@Reducer
struct InvoiceDetailFeature {
    /// Observable state for the invoice detail screen.
    @ObservableState
    struct State: Equatable {
        /// The invoice being displayed.
        var invoice: FlexiBeeInvoice
        /// Line items fetched from FlexiBee for the invoice.
        var lineItems: [FlexiBeeInvoiceItem] = []
        /// Whether the initial load (line items, movement, cash receipt) is in progress.
        var isLoading: Bool = false
        /// The associated stock movement record, if one has been created.
        var stockMovement: FlexiBeeStockMovement?
        /// Items belonging to the linked stock movement.
        var stockMovementItems: [FlexiBeeStockMovementItem] = []
        /// FlexiBee document ID of the cash receipt linked to this invoice, if any.
        var cashReceiptId: String?
        /// Whether a PDF is currently being fetched for sharing.
        var isLoadingPDF: Bool = false
        /// Loaded PDF data ready to be presented in a share sheet.
        var pdfShareItem: PDFShareItem?
        @Presents var destination: Destination.State?

        /// Whether the invoice can still be edited (unpaid invoices only).
        var canEdit: Bool { invoice.paymentStatus != .paid }
        /// Whether a stock-movement record has already been created for this invoice.
        var stockMovementCreated: Bool { stockMovement != nil }
        /// Whether the invoice has been marked as accounted in FlexiBee.
        var isAccounted: Bool { invoice.isAccounted == true }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.invoice == rhs.invoice &&
            lhs.lineItems.map(\.id) == rhs.lineItems.map(\.id) &&
            lhs.isLoading == rhs.isLoading &&
            lhs.stockMovement?.id == rhs.stockMovement?.id &&
            lhs.stockMovementItems.map(\.id) == rhs.stockMovementItems.map(\.id) &&
            lhs.cashReceiptId == rhs.cashReceiptId &&
            lhs.isLoadingPDF == rhs.isLoadingPDF
        }
    }

    // MARK: - Destination

    /// All modal destinations reachable from the invoice detail screen.
    @Reducer
    struct Destination {
        /// Union of possible presentation states.
        @ObservableState
        enum State: Equatable {
            case editForm(InvoiceFormPlaceholderFeature.State)
            case stockMovement(StockMovementPlaceholderFeature.State)
            case statusChange(StatusChangeFeature.State)
            case deleteAlert(ConfirmationDialogFeature.State)
        }
        enum Action {
            case editForm(InvoiceFormPlaceholderFeature.Action)
            case stockMovement(StockMovementPlaceholderFeature.Action)
            case statusChange(StatusChangeFeature.Action)
            case deleteAlert(ConfirmationDialogFeature.Action)
        }
        var body: some Reducer<State, Action> {
            Reduce { _, _ in .none }
                .ifCaseLet(\.editForm, action: \.editForm) { InvoiceFormPlaceholderFeature() }
                .ifCaseLet(\.stockMovement, action: \.stockMovement) { StockMovementPlaceholderFeature() }
                .ifCaseLet(\.statusChange, action: \.statusChange) { StatusChangeFeature() }
                .ifCaseLet(\.deleteAlert, action: \.deleteAlert) { ConfirmationDialogFeature() }
        }
    }

    // MARK: - Action

    enum Action {
        case onLoad
        case loaded(
            items: [FlexiBeeInvoiceItem],
            movement: FlexiBeeStockMovement?,
            movementItems: [FlexiBeeStockMovementItem],
            cashReceiptId: String?
        )
        case editTapped
        case deleteTapped
        case deleteConfirmed
        case deleteCompleted
        case deleteCancelled
        case setPaymentStatus(PaymentStatus, PaymentMethod?)
        case statusChangeConfirmed(PaymentStatus, PaymentMethod)
        case statusChangeCompleted(FlexiBeeInvoice)
        case openStockMovement
        case stockMovementCreated
        case accountingTapped
        case accountingCompleted(FlexiBeeInvoice)
        case shareInvoicePDF
        case shareCashReceiptPDF
        case shareBothPDFs
        case pdfLoaded(PDFShareItem)
        case pdfShareDismissed
        case invoiceRefreshed(FlexiBeeInvoice)
        case destination(PresentationAction<Destination.Action>)
        case failed(String)
        case productTapped(String)
        case clientTapped
    }

    // MARK: - Dependencies

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.authClient) var authClient

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.isLoading = true
                let invoiceId = state.invoice.id
                let invoiceNumber = state.invoice.invoiceNumber
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        let rawItems = try await flexiBeeClient.fetchLineItemsForInvoice(invoiceId)
                        let items = await MainActor.run { rawItems.filter { !$0.productName.isEmpty && $0.quantity > 0 } }
                        let movementResult = try? await flexiBeeClient.fetchStockMovement(invoiceNumber)
                        let cashId = try? await flexiBeeClient.fetchCashReceiptId(invoiceId)
                        await send(.loaded(
                            items: items,
                            movement: movementResult?.0,
                            movementItems: movementResult?.1 ?? [],
                            cashReceiptId: cashId
                        ))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .loaded(items, movement, movementItems, cashReceiptId):
                state.isLoading = false
                state.lineItems = items
                state.stockMovement = movement
                state.stockMovementItems = movementItems
                state.cashReceiptId = cashReceiptId
                return .none

            case .editTapped:
                state.destination = .editForm(InvoiceFormPlaceholderFeature.State(editingInvoice: state.invoice))
                return .none

            case .deleteTapped:
                state.destination = .deleteAlert(ConfirmationDialogFeature.State())
                return .none

            case .deleteConfirmed:
                let invoiceId = state.invoice.id
                let invoiceNumber = state.invoice.invoiceNumber
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        try await flexiBeeClient.deleteStockMovement(invoiceNumber)
                        try await flexiBeeClient.deleteInvoice(invoiceId)
                        await send(.deleteCompleted)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .deleteCompleted:
                return .none

            case .deleteCancelled:
                return .none

            case let .setPaymentStatus(status, method):
                state.destination = .statusChange(StatusChangeFeature.State(
                    status: status,
                    method: method ?? .prevod
                ))
                return .none

            case let .statusChangeConfirmed(status, method):
                state.destination = nil
                let invoiceId = state.invoice.id
                let invoice = state.invoice
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        if status == .paid, method == .hotove {
                            try await flexiBeeClient.createCashReceipt(invoice)
                        }
                        try await flexiBeeClient.updateInvoicePaymentStatus(invoiceId, status, method)
                        let updated = try await flexiBeeClient.fetchSingleInvoice(invoiceId) ?? invoice
                        await send(.statusChangeCompleted(updated))
                    } catch {
                        // Fallback: treat current invoice as unchanged
                        await send(.statusChangeCompleted(invoice))
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .statusChangeCompleted(invoice):
                state.invoice = invoice
                return .none

            case .accountingTapped:
                let invoiceId = state.invoice.id
                let invoice = state.invoice
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        try await flexiBeeClient.markAsAccounted(invoiceId)
                        let updated = try await flexiBeeClient.fetchSingleInvoice(invoiceId) ?? invoice
                        await send(.accountingCompleted(updated))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .accountingCompleted(invoice):
                state.invoice = invoice
                return .none

            case .openStockMovement:
                state.destination = .stockMovement(StockMovementPlaceholderFeature.State(
                    invoiceId: state.invoice.id,
                    invoiceNumber: state.invoice.invoiceNumber,
                    lineItems: state.lineItems
                ))
                return .none

            case .stockMovementCreated:
                // Reload to pick up the newly created movement
                return .send(.onLoad)

            case .shareInvoicePDF:
                state.isLoadingPDF = true
                let path = "/faktura-vydana/\(state.invoice.id).pdf"
                let filename = "\(state.invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        let data = try await flexiBeeClient.fetchPDF(path)
                        await send(.pdfLoaded(PDFShareItem(data: data, filename: filename)))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .shareCashReceiptPDF:
                guard let rid = state.cashReceiptId else { return .none }
                state.isLoadingPDF = true
                let path = "/pokladni-pohyb/\(rid).pdf"
                let filename = "receipt-\(state.invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        let data = try await flexiBeeClient.fetchPDF(path)
                        await send(.pdfLoaded(PDFShareItem(data: data, filename: filename)))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .shareBothPDFs:
                guard let rid = state.cashReceiptId else {
                    return .send(.shareInvoicePDF)
                }
                state.isLoadingPDF = true
                let invoicePath = "/faktura-vydana/\(state.invoice.id).pdf"
                let receiptPath = "/pokladni-pohyb/\(rid).pdf"
                let invoiceName = "\(state.invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
                let receiptName = "receipt-\(state.invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    do {
                        async let invData = flexiBeeClient.fetchPDF(invoicePath)
                        async let recData = flexiBeeClient.fetchPDF(receiptPath)
                        let (inv, rec) = try await (invData, recData)
                        await send(.pdfLoaded(PDFShareItem(files: [(inv, invoiceName), (rec, receiptName)])))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .pdfLoaded(item):
                state.isLoadingPDF = false
                state.pdfShareItem = item
                return .none

            case .pdfShareDismissed:
                state.pdfShareItem = nil
                return .none

            case let .invoiceRefreshed(invoice):
                state.invoice = invoice
                return .none

            case .destination(.presented(.editForm(.submitted))):
                state.destination = nil
                let id = state.invoice.id
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    if let updated = try? await flexiBeeClient.fetchSingleInvoice(id) {
                        await send(.invoiceRefreshed(updated))
                    }
                    await send(.onLoad)
                }

            case .destination(.presented(.editForm(.dismiss))):
                state.destination = nil
                return .none

            case .destination(.presented(.statusChange(.confirmed(let status, let method)))):
                return .send(.statusChangeConfirmed(status, method))

            case .destination(.presented(.statusChange(.cancelled))):
                state.destination = nil
                return .none

            case .destination(.presented(.stockMovement(.submitted))):
                state.destination = nil
                return .send(.stockMovementCreated)

            case .destination(.presented(.stockMovement(.skipped))):
                state.destination = nil
                return .none

            case .destination(.presented(.deleteAlert(.confirmed))):
                return .send(.deleteConfirmed)

            case .destination(.presented(.deleteAlert(.cancelled))):
                state.destination = nil
                return .none

            case .destination(.dismiss):
                return .none

            case .destination:
                return .none

            case let .failed(msg):
                state.isLoading = false
                state.isLoadingPDF = false
                _ = msg
                return .none

            case .productTapped:
                return .none

            case .clientTapped:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) { Destination() }
    }
}

// MARK: - StatusChangeFeature

/// Minimal TCA feature that holds the payment status and method the user is about to confirm.
@Reducer
struct StatusChangeFeature {
    /// Transient state for the payment-method picker sheet.
    @ObservableState
    struct State: Equatable {
        /// The target payment status being set.
        var status: PaymentStatus
        /// The payment method selected by the user.
        var method: PaymentMethod
    }

    enum Action {
        case confirmed(PaymentStatus, PaymentMethod)
        case cancelled
        case methodChanged(PaymentMethod)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .methodChanged(method):
                state.method = method
                return .none
            case .confirmed, .cancelled:
                return .none
            }
        }
    }
}

// MARK: - StockMovementPlaceholderFeature

/// Thin TCA wrapper that carries the data needed to bootstrap `StockMovementScreen` from a TCA context.
@Reducer
struct StockMovementPlaceholderFeature {
    /// Data required to pre-fill the stock-movement form.
    @ObservableState
    struct State: Equatable {
        /// FlexiBee ID of the parent invoice.
        var invoiceId: String
        /// Human-readable invoice number used as the movement description.
        var invoiceNumber: String
        /// Pre-filled line items from the invoice, converted to movement drafts.
        var lineItems: [FlexiBeeInvoiceItem] = []
    }

    enum Action {
        /// User submitted the stock movement form successfully.
        case submitted
        /// User dismissed the form without creating a movement.
        case skipped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

// MARK: - ConfirmationDialogFeature

/// Generic two-button (confirm / cancel) alert feature, used for the delete-invoice confirmation.
@Reducer
struct ConfirmationDialogFeature {
    /// Empty state — the alert carries no additional data.
    @ObservableState
    struct State: Equatable {}

    enum Action {
        /// User confirmed the destructive action.
        case confirmed
        /// User cancelled and dismissed the alert.
        case cancelled
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}
