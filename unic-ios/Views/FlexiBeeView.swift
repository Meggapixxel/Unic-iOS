import SwiftUI

// MARK: - Main FlexiBee View

struct FlexiBeeView: View {
    @StateObject private var viewModel = FlexiBeeViewModel()
    @State private var router = AppRouter()

    var body: some View {
        AppNavigationStack(router: router) {
            StockSectionView(viewModel: viewModel)
                .navigationTitle("FlexiBee")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .searchable(text: $viewModel.searchText, prompt: String(localized: "search_stock"))
                .overlay { if viewModel.isLoading { LoadingOverlay() } }
                .overlay { if viewModel.isSearchingBarcode { LoadingOverlay(text: String.barcode_searching) } }
                .task { await viewModel.loadIfNeeded() }
                .onChange(of: viewModel.foundProduct) { _, product in
                    if let product {
                        router.push(.product(product))
                        viewModel.foundProduct = nil
                    }
                }
                .fullScreenCover(isPresented: $viewModel.showBarcodeScanner) {
                    BarcodeScannerScreen(
                        onScan: { barcode in Task { await viewModel.handleScannedBarcode(barcode) } },
                        onDismiss: { viewModel.showBarcodeScanner = false }
                    )
                }
                .alert(String.barcode_title, isPresented: .init(
                    get: { viewModel.barcodeError != nil },
                    set: { if !$0 { viewModel.barcodeError = nil } }
                )) {
                    Button("OK") { viewModel.barcodeError = nil }
                } message: {
                    Text(viewModel.barcodeError ?? "")
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { viewModel.sortAscending.toggle() } label: {
                Image(systemName: viewModel.sortAscending ? "arrow.up.circle" : "arrow.down.circle")
                    .imageScale(.large)
            }
        }
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { viewModel.showBarcodeScanner = true } label: {
                Image(systemName: "barcode.viewfinder").imageScale(.large)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SyncButton(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate) {
                Task { await viewModel.forceSync() }
            }
        }
    }
}

// MARK: - Stock Section

private struct StockSectionView: View {
    @ObservedObject var viewModel: FlexiBeeViewModel

    var body: some View {
        List {
            Section {
                statsRow.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Section {
                ForEach(viewModel.filteredStock) { item in
                    NavigationLink(value: AppDestination.product(item)) {
                        StockWithPriceRow(item: item)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.stock.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(String.stock_no_data, systemImage: "tray")
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(viewModel.stock.count)",           label: "SKU",              icon: "shippingbox",             color: .blue,   compact: true)
            StatCard(value: "\(Int(viewModel.totalStockUnits))",  label: String.stock_units, icon: "number.circle",           color: .green,  compact: true)
            StatCard(value: "\(viewModel.lowStockCount)",         label: String.stock_low,   icon: "exclamationmark.triangle",
                     color: viewModel.lowStockCount > 0 ? .orange : .secondary, compact: true)
        }
    }
}
