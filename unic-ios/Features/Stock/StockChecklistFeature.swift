// FILE: unic-ios/Features/Stock/StockChecklistFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Checklist Item

/// A single article-code entry in the stock checklist with an adjustable quantity.
struct StockChecklistItem: Identifiable, Equatable {
    let id: UUID
    /// FlexiBee article code used to identify the product.
    let code: String
    let name: String
    var quantity: Int

    init(id: UUID = UUID(), code: String, name: String, quantity: Int = 1) {
        self.id = id
        self.code = code
        self.name = name
        self.quantity = quantity
    }
}

// MARK: - StockChecklistFeature

/// Manages an ad-hoc stock-count checklist that accumulates items by barcode scanning and
/// lets the user adjust per-item quantities; the resulting list can be exported as a JSON payload.
///
/// **Entry point**
/// `.onLoad` is dispatched when the checklist sheet appears. It calls
/// `flexiBeeClient.loadIfNeeded()` to ensure the stock index is warm, then dispatches
/// `.loaded([])` — items start empty and are added exclusively through scanning.
///
/// **Key action flows**
/// - `.onLoad` — ensures the FlexiBee cache is populated; initialises `items` to an empty array.
/// - `.scanTapped` — sets `showScanner = true` to reveal the in-view barcode scanner.
/// - `.barcodeScanned(barcode)` — hides the scanner, sets `isLoading = true`, resolves the
///   barcode to a FlexiBee article via `firebaseClient.lookupBarcodeArticle`, matches the
///   normalised code against the local stock index, and dispatches `.barcodeSearchCompleted`.
/// - `.barcodeSearchCompleted(.success(item?))` — if a match is found, either increments the
///   quantity of an existing checklist entry or appends a new one with quantity 1; if no match
///   is found, sets `errorMessage` to a localised "barcode not found" string.
/// - `.barcodeSearchCompleted(.failure)` — surfaces `error.localizedDescription` in `errorMessage`.
/// - `.increment(code)` / `.decrement(code)` — adjust the quantity of an item by article code;
///   decrementing to zero removes the item from `items`.
/// - `.scannerDismissed` — resets `showScanner = false` (e.g. user dismisses without scanning).
/// - `.errorDismissed` — clears `errorMessage`.
/// - `.dismiss` — no-op at this layer; the parent feature (`StockFeature`) owns sheet dismissal.
///
/// **Navigation**
/// No `Path` or `Destination` reducers; navigation is limited to the `showScanner` bool flag
/// which the view uses to present an inline or sheet barcode-scanning component.
///
/// **Side effects**
/// - `flexiBeeClient.loadIfNeeded()` — ensures the local FlexiBee stock cache is up-to-date.
/// - `firebaseClient.lookupBarcodeArticle(_:)` — async Firebase read mapping a raw barcode
///   string to a FlexiBee article code, used to populate checklist entries.
@Reducer
struct StockChecklistFeature {
    /// Observable state for the stock checklist screen.
    @ObservableState
    struct State: Equatable {
        /// Items currently in the checklist, keyed by their UUID.
        var items: IdentifiedArrayOf<StockChecklistItem> = []
        /// `true` while the barcode scanner sheet is shown.
        var showScanner: Bool = false
        var isLoading: Bool = false
        var errorMessage: String?

        /// Sum of all item quantities in the checklist.
        var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }

        /// Pretty-printed JSON array suitable for pasting into FlexiBee or another system.
        var jsonPayload: String {
            let entries: [[String: Any]] = items.map { ["article": $0.code, "quantity": $0.quantity] }
            guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted),
                  let text = String(data: data, encoding: .utf8) else { return "[]" }
            return text
        }
    }

    enum Action {
        case onLoad
        case loaded([StockChecklistItem])
        /// Increments the quantity of the item with the given article code.
        case increment(String)
        /// Decrements the quantity of the item with the given article code, removing it when it reaches zero.
        case decrement(String)
        case scanTapped
        /// Sent when the camera scanner successfully reads a barcode string.
        case barcodeScanned(String)
        /// Sent with the result of looking up the scanned barcode in the FlexiBee stock index.
        case barcodeSearchCompleted(Result<StockChecklistItem?, Error>)
        case dismiss
        case scannerDismissed
        case errorDismissed
    }

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.firebaseClient) var firebaseClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.isLoading = true
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.loadIfNeeded()
                    // Items start empty — they are added via scanning or manual entry
                    await send(.loaded([]))
                }

            case let .loaded(items):
                state.isLoading = false
                state.items = IdentifiedArray(uniqueElements: items)
                return .none

            case let .increment(code):
                guard let idx = state.items.firstIndex(where: { $0.code == code }) else { return .none }
                state.items[idx].quantity += 1
                return .none

            case let .decrement(code):
                guard let idx = state.items.firstIndex(where: { $0.code == code }) else { return .none }
                if state.items[idx].quantity > 1 {
                    state.items[idx].quantity -= 1
                } else {
                    state.items.remove(at: idx)
                }
                return .none

            case .scanTapped:
                state.showScanner = true
                return .none

            case let .barcodeScanned(barcode):
                state.showScanner = false
                state.isLoading = true
                let stockIndex: [(normalized: String, code: String, name: String)] =
                    Array(flexiBeeClient.stockWithPrices()).map { (normalize($0.code), $0.code, $0.name) }
                let firebaseClient = firebaseClient
                return .run { [stockIndex, firebaseClient] send in
                    do {
                        guard let article = try await firebaseClient.lookupBarcodeArticle(barcode) else {
                            await send(.barcodeSearchCompleted(.success(nil)))
                            return
                        }
                        let normalized = normalize(article)
                        guard let match = stockIndex.first(where: { $0.normalized == normalized }) else {
                            await send(.barcodeSearchCompleted(.success(nil)))
                            return
                        }
                        let item = StockChecklistItem(code: match.code, name: match.name, quantity: 1)
                        await send(.barcodeSearchCompleted(.success(item)))
                    } catch {
                        await send(.barcodeSearchCompleted(.failure(error)))
                    }
                }

            case let .barcodeSearchCompleted(.success(item)):
                state.isLoading = false
                if let item {
                    if let idx = state.items.firstIndex(where: { normalize($0.code) == normalize(item.code) }) {
                        state.items[idx].quantity += 1
                    } else {
                        state.items.append(item)
                    }
                } else {
                    state.errorMessage = String.barcode_not_found("—")
                }
                return .none

            case let .barcodeSearchCompleted(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .dismiss:
                return .none

            case .scannerDismissed:
                state.showScanner = false
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none
            }
        }
    }
}

/// Strips all non-alphanumeric characters from a string and uppercases the result for barcode comparison.
/// - Parameter s: The raw article code or barcode string to normalise.
/// - Returns: An uppercase alphanumeric-only string.
nonisolated private func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
     .uppercased()
}
