import Foundation
import Combine
import FirebaseFirestore
import SwiftUI

// MARK: - Model

struct ChecklistItem: Identifiable {
    let id = UUID()
    let product: FlexiBeeStockWithPrice
    var quantity: Int
}

// MARK: - ViewModel

@MainActor
final class StockChecklistViewModel: ObservableObject {
    @Published var items: [ChecklistItem] = []
    @Published var showScanner = false
    @Published var isSearchingBarcode = false
    @Published var barcodeError: String?

    private let service = FlexiBeeService.shared
    private let db = Firestore.firestore()

    var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }

    var jsonPayload: String {
        let entries: [[String: Any]] = items.map { ["article": $0.product.code, "quantity": $0.quantity] }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    func loadIfNeeded() async {
        await service.loadIfNeeded()
    }

    func increment(_ item: ChecklistItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].quantity += 1
    }

    func decrement(_ item: ChecklistItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if items[idx].quantity > 1 {
            items[idx].quantity -= 1
        } else {
            items.remove(at: idx)
        }
    }

    func handleScannedBarcode(_ barcode: String) async {
        showScanner = false
        barcodeError = nil
        isSearchingBarcode = true
        defer { isSearchingBarcode = false }

        do {
            let doc = try await db.collection("barcodes").document(barcode).getDocument()
            guard doc.exists, let article = doc.data()?["article"] as? String else {
                barcodeError = String.barcode_not_found(barcode)
                return
            }
            guard let product = service.stockWithPrices.first(where: {
                normalize($0.code) == normalize(article)
            }) else {
                barcodeError = String.barcode_not_found(article)
                return
            }
            if let idx = items.firstIndex(where: { normalize($0.product.code) == normalize(product.code) }) {
                items[idx].quantity += 1
            } else {
                items.append(ChecklistItem(product: product, quantity: 1))
            }
        } catch {
            barcodeError = String.barcode_search_error(error.localizedDescription)
        }
    }

    private func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
         .uppercased()
    }
}
