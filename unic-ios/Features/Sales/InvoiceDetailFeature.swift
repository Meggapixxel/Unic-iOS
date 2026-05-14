// FILE: unic-ios/Features/Sales/InvoiceDetailFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - InvoiceDetailFeature

@Reducer
struct InvoiceDetailFeature {
    @ObservableState
    struct State: Equatable {
        var invoice: FlexiBeeInvoice
        var lineItems: [FlexiBeeInvoiceItem] = []
        var isLoading: Bool = false
        var stockMovement: FlexiBeeStockMovement?
        var stockMovementItems: [FlexiBeeStockMovementItem] = []
        var cashReceiptId: String?
        var isLoadingPDF: Bool = false
        var pdfShareItem: PDFShareItem?
        @Presents var destination: Destination.State?

        var canEdit: Bool { invoice.paymentStatus != .paid }
        var stockMovementCreated: Bool { stockMovement != nil }

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

    @Reducer
    struct Destination {
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

            case .openStockMovement:
                state.destination = .stockMovement(StockMovementPlaceholderFeature.State(
                    invoiceId: state.invoice.id,
                    invoiceNumber: state.invoice.invoiceNumber
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

@Reducer
struct StatusChangeFeature {
    @ObservableState
    struct State: Equatable {
        var status: PaymentStatus
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

@Reducer
struct StockMovementPlaceholderFeature {
    @ObservableState
    struct State: Equatable {
        var invoiceId: String
        var invoiceNumber: String
    }

    enum Action {
        case submitted
        case skipped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

// MARK: - ConfirmationDialogFeature

@Reducer
struct ConfirmationDialogFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action {
        case confirmed
        case cancelled
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}
