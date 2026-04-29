import Foundation
import SwiftUI
import Combine

@MainActor
final class FlexiBeeViewModel: ObservableObject {
    @Published var searchText = ""

    private let service = FlexiBeeService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward service changes to this ViewModel so views re-render
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
    var lowStockCount: Int { service.stock.filter { $0.quantity <= 2 }.count }

    // MARK: - View-specific

    var filteredStock: [FlexiBeeStockWithPrice] {
        let base = service.stockWithPrices
        if searchText.isEmpty { return base.sorted { $0.quantity > $1.quantity } }
        let q = searchText.lowercased()
        return base
            .filter { $0.kod.lowercased().contains(q) || $0.nazev.lowercased().contains(q) }
            .sorted { $0.quantity > $1.quantity }
    }

    // MARK: - Actions

    func loadIfNeeded() async { await service.loadIfNeeded() }
    func forceSync() async { await service.forceSync() }
    func resetFilters() { searchText = "" }
}
