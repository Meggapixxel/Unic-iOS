// FILE: unic-ios/Features/Stock/StockFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Stock Feature
// StockSortField (.name / .code / .quantity) is defined in FlexiBeeScreen+ViewModel.swift

/// TCA reducer managing the Stock tab: loading warehouse data, search, sort, section collapse,
/// barcode scanning, and navigation to product detail and catalog.
@Reducer
struct StockFeature {
    /// Observable state for the Stock tab.
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var sortField: StockSortField = .section
        var sortAscending: Bool = true
        var isLoading: Bool = false
        var errorMessage: String?
        var lastSyncDate: Date?
        var path: StackState<Path.State> = StackState()
        @Presents var destination: Destination.State?

        // Backing store — populated on load/sync
        /// Raw list of all stock items; drives all derived computed properties.
        var allStock: [FlexiBeeStockItem] = []
        /// Product-line names that are currently collapsed in the section list.
        var collapsedSections: Set<String> = []

        /// Items after applying search text and sort order.
        var filteredStock: [FlexiBeeStockItem] {
            let q = searchText.lowercased()
            let items: [FlexiBeeStockItem] = searchText.isEmpty
                ? allStock
                : allStock.filter {
                    $0.code.lowercased().contains(q) ||
                    $0.productName.lowercased().contains(q) ||
                    $0.productLine.lowercased().contains(q)
                }
            switch sortField {
            case .section:
                return items.sorted { $0.productName < $1.productName }
            case .name:
                return items.sorted { $0.productName < $1.productName }
            case .quantity:
                return items.sorted { sortAscending ? $0.quantity < $1.quantity : $0.quantity > $1.quantity }
            }
        }

        /// Sum of quantities across all stock items.
        var totalStockUnits: Double { allStock.reduce(0) { $0 + $1.quantity } }
        /// Number of items with 2 or fewer units remaining.
        var lowStockCount: Int { allStock.filter { $0.quantity <= 2 }.count }

        /// Filtered stock grouped by product line, with unknown lines sorted last.
        var groupedStock: [(line: String, items: [FlexiBeeStockItem])] {
            let grouped = Dictionary(grouping: filteredStock, by: \.productLine)
            return grouped.keys.sorted { a, b in
                if a == "—" { return false }
                if b == "—" { return true }
                return a < b
            }.map { line in (line: line, items: grouped[line]!) }
        }
    }

    // MARK: - Path

    @Reducer
    enum Path {
        case productDetail(ProductDetailFeature)
        case catalog(CatalogFeature)
    }

    // MARK: - Destination

    @Reducer
    enum Destination {
        case checklist(StockChecklistFeature)
        case barcodeScanner(BarcodeScannerFeature)
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case forceSync
        case syncCompleted([FlexiBeeStockItem], Date?)
        case syncFailed(String)
        case destinationChanged
        case toggleSection(String)
        case collapseAll([String])
        case expandAll
        case openProduct(FlexiBeeStockItem)
        case openChecklist
        case openBarcodeScanner
        case openCatalog
        case barcodeScanned(String)
        case barcodeSearchCompleted(FlexiBeeStockItem?)
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<Path>)
    }

    // MARK: - Dependencies

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.firebaseClient) var firebaseClient

    // MARK: - Body

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {

            case .onLoad:
                state.isLoading = flexiBeeClient.isLoading()
                state.lastSyncDate = flexiBeeClient.lastSyncDate()
                let stock = flexiBeeClient.stockWithPrices()
                if !stock.isEmpty {
                    state.allStock = Array(stock)
                    state.isLoading = false
                }
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.loadIfNeeded()
                    let (updated, syncDate) = await MainActor.run { (Array(flexiBeeClient.stockWithPrices()), flexiBeeClient.lastSyncDate()) }
                    await send(.syncCompleted(updated, syncDate))
                }

            case .forceSync:
                state.isLoading = true
                state.errorMessage = nil
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                    let (stock, syncDate) = await MainActor.run { (Array(flexiBeeClient.stockWithPrices()), flexiBeeClient.lastSyncDate()) }
                    await send(.syncCompleted(stock, syncDate))
                }

            case let .syncCompleted(stock, date):
                state.isLoading = false
                state.allStock = stock
                state.lastSyncDate = date
                return .none

            case let .syncFailed(msg):
                state.isLoading = false
                state.errorMessage = msg
                return .none

            case let .toggleSection(line):
                if state.collapsedSections.contains(line) {
                    state.collapsedSections.remove(line)
                } else {
                    state.collapsedSections.insert(line)
                }
                return .none

            case let .collapseAll(lines):
                state.collapsedSections = Set(lines)
                return .none

            case .expandAll:
                state.collapsedSections = []
                return .none

            case .destinationChanged:
                return .none

            case let .openProduct(product):
                state.path.append(.productDetail(ProductDetailFeature.State(product: product)))
                return .none

            case .openCatalog:
                state.path.append(.catalog(CatalogFeature.State()))
                return .none

            case .openChecklist:
                state.destination = .checklist(StockChecklistFeature.State())
                return .none

            case .openBarcodeScanner:
                state.destination = .barcodeScanner(BarcodeScannerFeature.State())
                return .none

            case let .barcodeScanned(barcode):
                state.destination = nil
                let stockIndex = state.allStock.map { (normalized: Self.normalizeKod($0.code), product: $0) }
                let firebaseClient = firebaseClient
                return .run { [stockIndex, firebaseClient] send in
                    do {
                        guard let article = try await firebaseClient.lookupBarcodeArticle(barcode) else {
                            await send(.barcodeSearchCompleted(nil))
                            return
                        }
                        let normalized = Self.normalizeKod(article)
                        let product = stockIndex.first { $0.normalized == normalized }?.product
                        await send(.barcodeSearchCompleted(product))
                    } catch {
                        await send(.barcodeSearchCompleted(nil))
                    }
                }

            case let .barcodeSearchCompleted(product):
                if let product {
                    state.path.append(.productDetail(ProductDetailFeature.State(product: product)))
                }
                return .none

            case .destination(.presented(.barcodeScanner(.scanCompleted(let barcode)))):
                return .send(.barcodeScanned(barcode))

            case .destination(.presented(.barcodeScanner(.dismiss))):
                state.destination = nil
                return .none

            case .destination(.presented(.checklist(.dismiss))):
                state.destination = nil
                return .none

            case .destination:
                return .none

            case .binding:
                return .none

            case .path:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path)
    }

    /// Strips all non-alphanumeric characters and uppercases an article code for barcode matching.
    /// - Parameter s: Raw article code string.
    /// - Returns: Normalized uppercase code with punctuation removed.
    nonisolated private static func normalizeKod(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
         .uppercased()
    }
}

extension StockFeature.Path.State: Equatable {}

// MARK: - Product Detail Feature (leaf)

/// Leaf TCA reducer for the product detail screen showing stock level and pricing.
@Reducer
struct ProductDetailFeature {
    /// Observable state for a single product's detail view.
    @ObservableState
    struct State: Equatable {
        /// The stock item being displayed.
        var product: FlexiBeeStockItem
        /// When `true`, the purchase price row is visible.
        var showPurchaseDetails: Bool = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case togglePurchaseDetails
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .togglePurchaseDetails:
                state.showPurchaseDetails.toggle()
                return .none
            case .binding:
                return .none
            }
        }
    }
}

// MARK: - Barcode Scanner Feature (leaf)

/// Minimal leaf TCA reducer that bridges the camera barcode scanner to the parent feature.
@Reducer
struct BarcodeScannerFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action {
        case scanCompleted(String)
        case dismiss
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

extension StockFeature.Destination.State: Equatable {}
