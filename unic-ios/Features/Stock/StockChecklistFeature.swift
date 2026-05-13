// FILE: unic-ios/Features/Stock/StockChecklistFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Checklist Item

struct StockChecklistItem: Identifiable, Equatable {
    let id: UUID
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

@Reducer
struct StockChecklistFeature {
    @ObservableState
    struct State: Equatable {
        var items: IdentifiedArrayOf<StockChecklistItem> = []
        var showScanner: Bool = false
        var isLoading: Bool = false
        var errorMessage: String?

        var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }

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
        case increment(String)
        case decrement(String)
        case scanTapped
        case barcodeScanned(String)
        case barcodeSearchCompleted(Result<StockChecklistItem?, Error>)
        case dismiss
        case scannerDismissed
        case errorDismissed
    }

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.firebaseClient) var firebaseClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.isLoading = true
                return .run { send in
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
                let allStock = Array(flexiBeeClient.stockWithPrices())
                return .run { send in
                    do {
                        guard let article = try await firebaseClient.lookupBarcodeArticle(barcode) else {
                            await send(.barcodeSearchCompleted(.success(nil)))
                            return
                        }
                        let normalized = normalize(article)
                        guard let match = allStock.first(where: { normalize($0.code) == normalized }) else {
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

private func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
     .uppercased()
}
