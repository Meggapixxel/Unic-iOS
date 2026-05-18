// FILE: unic-ios/Features/Stock/StockFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Stock Feature
// StockSortField (.name / .code / .quantity) is defined in FlexiBeeScreen+ViewModel.swift

/// Manages the Stock tab, which displays all FlexiBee warehouse items grouped by product line.
/// Supports real-time search/sort, collapsible sections, barcode scanning, and navigation to
/// per-product detail and the in-app PDF catalog.
///
/// **Entry point**
/// `.onLoad` is dispatched when the Stock tab's view first appears (`.task` / `.onAppear`).
/// It immediately reads any already-cached items from `flexiBeeClient`, then calls
/// `flexiBeeClient.loadIfNeeded()` to refresh stale data in the background.
///
/// **Key action flows**
/// - `.onLoad` — seeds `allStock` from cache, then fires a background `loadIfNeeded()` task;
///   result arrives via `.syncCompleted`.
/// - `.forceSync` — sets `isLoading = true` and calls `flexiBeeClient.forceSync()`, which
///   triggers a full network refresh; result arrives via `.syncCompleted`.
/// - `.syncCompleted(stock, date)` — stores the refreshed item list and `lastSyncDate`.
/// - `.syncFailed(msg)` — clears the loading spinner and surfaces an error banner.
/// - `.toggleSection(line)` / `.collapseAll` / `.expandAll` — mutate `collapsedSections`
///   (a `Set<String>`) to show or hide product-line rows in the grouped list.
/// - `.openProduct(item)` — pushes a `ProductDetailFeature` onto the `NavigationStack` path.
/// - `.openCatalog` — pushes a `CatalogFeature` onto the path.
/// - `.openChecklist` — presents a `StockChecklistFeature` sheet via `Destination.checklist`.
/// - `.openBarcodeScanner` — presents a `BarcodeScannerFeature` sheet via `Destination.barcodeScanner`.
/// - `.barcodeScanned(barcode)` — dismisses the scanner, looks up the barcode article in
///   Firebase (`firebaseClient.lookupBarcodeArticle`), normalises the resulting article code,
///   matches it against `allStock`, and dispatches `.barcodeSearchCompleted`.
/// - `.barcodeSearchCompleted(product?)` — if a match was found, pushes `ProductDetailFeature`
///   onto the path; otherwise does nothing (error handling is silent at this layer).
///
/// **Navigation**
/// - `Path` (`NavigationStack`):
///   - `.productDetail(ProductDetailFeature)` — detail screen for a single stock item.
///   - `.catalog(CatalogFeature)` — in-app PDF catalog viewer with share capability.
/// - `Destination` (modal sheets):
///   - `.checklist(StockChecklistFeature)` — barcode-driven stocktake checklist with JSON export.
///   - `.barcodeScanner(BarcodeScannerFeature)` — camera barcode scanner; on success forwards
///     the scanned string back to the parent via `.barcodeScanned`.
///
/// **Side effects**
/// - `flexiBeeClient.loadIfNeeded()` / `flexiBeeClient.forceSync()` — network calls to the
///   FlexiBee ERP API; executed on a background `Effect.run`.
/// - `firebaseClient.lookupBarcodeArticle(_:)` — Firebase async read that maps a raw EAN/QR
///   barcode to a FlexiBee article code; used to open the correct product detail screen.
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
        case delegate(Delegate)

        enum Delegate: Equatable {
            case navigate(AppPath.State)
        }
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
                return .send(.delegate(.navigate(.productDetail(ProductDetailFeature.State(product: product)))))

            case .openCatalog:
                return .send(.delegate(.navigate(.catalog(CatalogFeature.State()))))

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
                    return .send(.delegate(.navigate(.productDetail(ProductDetailFeature.State(product: product)))))
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

            case .delegate:
                return .none

            case .binding:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    /// Strips all non-alphanumeric characters and uppercases an article code for barcode matching.
    /// - Parameter s: Raw article code string.
    /// - Returns: Normalized uppercase code with punctuation removed.
    nonisolated private static func normalizeKod(_ s: String) -> String {
        s.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
         .uppercased()
    }
}

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
