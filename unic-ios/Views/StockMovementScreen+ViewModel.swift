import Foundation
import SwiftUI
import Combine

// MARK: - Bundle Section

/// One bundle/starter-kit item from the invoice.
/// Components are stock items that the user manually adds per section because
/// FlexiBee has no BOM (bill of materials) for bundle products.
struct BundleSection: Identifiable {
    let id = UUID()
    let bundleName: String
    let bundleCode: String
    var components: [StockMovementItemDraft]
}

// MARK: - Pending Movement

/// Transfer object passed from `InvoiceDetailViewModel` to `StockMovementViewModel`.
/// `onMovementCreated` fires only on a successful API submit, not on skip,
/// so `InvoiceDetailViewModel.stockMovementCreated` correctly gates the "Paid" button.
struct PendingMovement {
    let invoiceId:         String
    let invoiceNumber:     String
    /// Regular (non-bundle) invoice items — pre-filled in the form.
    let items:             [InvoiceLineItemDraft]
    /// One section per bundle in the invoice — user adds individual components to each.
    let bundleSections:    [BundleSection]
    var onMovementCreated: (() async -> Void)? = nil

    init(
        invoiceId: String,
        invoiceNumber: String,
        items: [InvoiceLineItemDraft],
        bundleSections: [BundleSection] = [],
        onMovementCreated: ((() async -> Void))? = nil
    ) {
        self.invoiceId = invoiceId
        self.invoiceNumber = invoiceNumber
        self.items = items
        self.bundleSections = bundleSections
        self.onMovementCreated = onMovementCreated
    }
}

// MARK: - Draft

/// Mutable draft for a single stock movement line.
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

/// Drives `StockMovementScreen`.
///
/// Layout:
/// - Regular items section: pre-filled from non-bundle invoice line items, editable.
/// - Bundle sections: one per starter-kit in the invoice. User manually adds components
///   (individual stock items) because FlexiBee has no BOM for bundles.
///
/// `submit()` combines regular items + all bundle components into a single STANDARD movement.
@MainActor
final class StockMovementViewModel: ObservableObject {
    @Published var items: [StockMovementItemDraft]
    @Published var bundleSections: [BundleSection]
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    @Published private(set) var didSucceed = false
    @Published private(set) var submittedMovement = false

    let invoiceId:     String
    let invoiceNumber: String
    private let onMovementCreated: (() async -> Void)?

    /// Computed so the picker always reflects the latest price list from `FlexiBeeService`.
    var priceList: [FlexiBeeCenikItem] { FlexiBeeService.shared.priceList }

    var isValid: Bool {
        items.contains { $0.isValid } ||
        bundleSections.contains { $0.components.contains { $0.isValid } }
    }

    init(pending: PendingMovement) {
        invoiceId         = pending.invoiceId
        invoiceNumber     = pending.invoiceNumber
        onMovementCreated = pending.onMovementCreated

        var tempItems = pending.items.compactMap { draft -> StockMovementItemDraft? in
            guard let code = draft.productCode, !code.isEmpty, draft.quantityDouble > 0 else { return nil }
            return StockMovementItemDraft(productCode: code, productName: draft.name, quantity: draft.quantityDouble)
        }
        // Ensure at least one blank row when there are no pre-filled items and no bundle sections
        if tempItems.isEmpty && pending.bundleSections.isEmpty { tempItems = [StockMovementItemDraft()] }
        items = tempItems

        bundleSections = pending.bundleSections
    }

    /// Adds a new empty component draft to the specified bundle section.
    /// Returns the new draft's `id` so the caller can immediately open the product picker for it.
    @discardableResult
    func addBundleComponent(to sectionId: UUID) -> UUID? {
        guard let idx = bundleSections.firstIndex(where: { $0.id == sectionId }) else { return nil }
        let draft = StockMovementItemDraft()
        bundleSections[idx].components.append(draft)
        return draft.id
    }

    func removeBundleComponent(from sectionId: UUID, at offsets: IndexSet) {
        guard let idx = bundleSections.firstIndex(where: { $0.id == sectionId }) else { return }
        bundleSections[idx].components.remove(atOffsets: offsets)
    }

    /// Creates a `code:STANDARD` movement in FlexiBee with all regular items + bundle components,
    /// then fires `onMovementCreated` to unlock the "Paid" button in `InvoiceDetailViewModel`.
    func submit() async {
        isSubmitting = true
        submitError = nil

        var lines: [NewStockMovementLine] = []
        lines += items.filter { $0.isValid }.map {
            NewStockMovementLine(productCode: "code:\($0.productCode)", quantity: $0.quantityDouble)
        }
        for section in bundleSections {
            lines += section.components.filter { $0.isValid }.map {
                NewStockMovementLine(productCode: "code:\($0.productCode)", quantity: $0.quantityDouble)
            }
        }

        guard !lines.isEmpty else {
            didSucceed = true
            isSubmitting = false
            return
        }
        let movement = NewStockMovement(
            description: "Vydej k \(invoiceNumber)",
            lines: lines
        )
        do {
            try await FlexiBeeService.shared.createStockMovement(movement)
            submittedMovement = true
            await onMovementCreated?()
            await FlexiBeeService.shared.forceSync()
            didSucceed = true
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }

    /// Dismisses without creating a movement and without firing `onMovementCreated`,
    /// so the "Paid" button stays locked until the user returns and submits.
    func skip() { didSucceed = true }
}
