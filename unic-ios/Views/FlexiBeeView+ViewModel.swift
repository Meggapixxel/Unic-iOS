import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

/// Thin proxy over `FlexiBeeService` for the stock inventory screen.
/// Exists to keep view-specific state (search, sort, barcode UI) separate from the shared service.
@MainActor
final class FlexiBeeViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortAscending = false
    @Published var showBarcodeScanner = false
    @Published var isSearchingBarcode = false
    @Published var foundProduct: FlexiBeeStockWithPrice?
    @Published var barcodeError: String?

    private let service = FlexiBeeService.shared
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Propagate service updates so the view re-renders when stock data refreshes
        // without holding a direct @ObservedObject reference to the service.
        service.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Forwarded from service

    var stock: [FlexiBeeStockCard] { service.stock }
    var isLoading: Bool { service.isLoading }
    var errorMessage: String? { service.errorMessage }
    var lastSyncDate: Date? { service.lastSyncDate }
    var totalStockUnits: Double { service.stock.reduce(0) { $0 + $1.quantity } }
    /// Items with quantity ≤ 2 are considered low stock.
    var lowStockCount: Int { service.stock.filter { $0.quantity <= 2 }.count }

    // MARK: - View-specific

    /// Filtering and sorting are applied in-memory over the service's cached list — no separate cache needed.
    var filteredStock: [FlexiBeeStockWithPrice] {
        let base = service.stockWithPrices
        let q = searchText.lowercased()
        let items: [FlexiBeeStockWithPrice] = searchText.isEmpty
            ? Array(base)
            : base.filter { $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q) }
        return items.sorted { sortAscending ? $0.quantity < $1.quantity : $0.quantity > $1.quantity }
    }

    // MARK: - Actions

    func loadIfNeeded() async { await service.loadIfNeeded() }
    func forceSync() async { await service.forceSync() }
    func resetFilters() { searchText = "" }

    /// Strips non-alphanumeric characters and uppercases so barcode article codes
    /// match FlexiBee product codes regardless of formatting differences (dashes, spaces, etc.).
    private func normalizeKod(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
         .uppercased()
    }

    /// Barcode lookup flow: Firestore `barcodes/{barcode}` → article code → matched against
    /// in-memory `stockWithPrices` using normalized code comparison.
    func handleScannedBarcode(_ barcode: String) async {
        showBarcodeScanner = false
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
                normalizeKod($0.code) == normalizeKod(article)
            }) else {
                barcodeError = String.barcode_not_found(article)
                return
            }
            foundProduct = product
        } catch {
            barcodeError = String.barcode_search_error(error.localizedDescription)
        }
    }
}
