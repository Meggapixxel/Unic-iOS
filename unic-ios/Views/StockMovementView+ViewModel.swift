import Foundation
import Combine

// MARK: - Draft

struct StockMovementItemDraft: Identifiable {
    let id = UUID()
    var productCode: String
    var productName: String
    var quantity:    String

    var quantityDouble: Double { Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var isValid: Bool { !productCode.isEmpty && quantityDouble > 0 }

    init(productCode: String = "", productName: String = "", quantity: Double = 1) {
        self.productCode = productCode
        self.productName = productName
        self.quantity    = quantity > 0 ? String(format: "%g", quantity) : "1"
    }
}

// MARK: - ViewModel

@MainActor
final class StockMovementViewModel: ObservableObject {
    @Published var items: [StockMovementItemDraft]
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    @Published private(set) var didSucceed = false

    let invoiceId:     String
    let invoiceNumber: String
    let priceList:     [FlexiBeeCenikItem]

    var isValid: Bool { items.contains { $0.isValid } }

    init(pending: PendingMovement) {
        invoiceId     = pending.invoiceId
        invoiceNumber = pending.invoiceNumber
        priceList     = pending.priceList
        // Pre-fill items that were picked from the price list (have a ceník code)
        items = pending.items.compactMap { draft in
            guard let code = draft.productCode, !code.isEmpty, draft.quantityDouble > 0 else { return nil }
            return StockMovementItemDraft(productCode: code, productName: draft.name, quantity: draft.quantityDouble)
        }
        if items.isEmpty { items = [StockMovementItemDraft()] }
    }

    func submit() async {
        isSubmitting = true
        submitError = nil
        let lines = items.filter { $0.isValid }.map {
            NewStockMovementLine(productCode: "code:\($0.productCode)", quantity: $0.quantityDouble)
        }
        guard !lines.isEmpty else {
            didSucceed = true
            isSubmitting = false
            return
        }
        let movement = NewStockMovement(
            documentType: "code:STANDARD",
            description: "Vydej k \(invoiceNumber)",
            lines: lines
        )
        do {
            try await FlexiBeeService.shared.createStockMovement(movement)
            didSucceed = true
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }

    func skip() { didSucceed = true }
}
