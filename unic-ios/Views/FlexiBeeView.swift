import SwiftUI

// MARK: - Main FlexiBee View

struct FlexiBeeView: View {
    @StateObject private var viewModel = FlexiBeeViewModel()
    @State private var router = AppRouter()

    var body: some View {
        AppNavigationStack(router: router) {
            StockSectionView(viewModel: viewModel)
                .navigationTitle(String.stock_nav_title)
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
            Menu {
                Picker(selection: $viewModel.sortField) {
                    Text(String.stock_sort_quantity).tag(StockSortField.quantity)
                    Text(String.stock_sort_code).tag(StockSortField.code)
                    Text(String.stock_sort_name).tag(StockSortField.name)
                } label: { EmptyView() }
                Divider()
                Picker(selection: $viewModel.sortAscending) {
                    Text(String.stock_sort_asc).tag(true)
                    Text(String.stock_sort_desc).tag(false)
                } label: { EmptyView() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
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
        ToolbarItem(placement: .topBarLeading) {
            Button { router.push(.stockChecklist) } label: {
                Image(systemName: "list.bullet.clipboard").imageScale(.large)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SyncDateLabel(isLoading: viewModel.isLoading, lastSyncDate: viewModel.lastSyncDate)
        }
    }
}

// MARK: - Stock Section

private struct StockSectionView: View {
    @ObservedObject var viewModel: FlexiBeeViewModel
    @State private var showScrollToTop = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    statsRow
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .id("top")
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: StockScrollOffsetKey.self,
                                    value: geo.frame(in: .global).minY
                                )
                            }
                        )
                }
                Section {
                    ForEach(viewModel.filteredStock) { item in
                        NavigationLink(value: AppDestination.product(item)) {
                            StockWithPriceRow(item: item)
                                .id("\(item.code)-\(item.quantity)")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.forceSync() }
            .onPreferenceChange(StockScrollOffsetKey.self) { y in
                showScrollToTop = y < 60
            }
            .overlay {
                if viewModel.stock.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(String.stock_no_data, systemImage: "tray")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToTop {
                    Button {
                        withAnimation { proxy.scrollTo("top", anchor: .top) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.blue, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: showScrollToTop)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(viewModel.stock.count)",          label: "SKU",             icon: "shippingbox",              color: .blue,                                              compact: true)
            StatCard(value: "\(Int(viewModel.totalStockUnits))", label: String.stock_units, icon: "number.circle",            color: .green,                                             compact: true)
            StatCard(value: "\(viewModel.lowStockCount)",        label: String.stock_low,   icon: "exclamationmark.triangle", color: viewModel.lowStockCount > 0 ? .orange : .secondary, compact: true)
        }
    }
}

// MARK: - Preference Key

private struct StockScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
