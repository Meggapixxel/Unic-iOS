// FILE: unic-ios/Features/Stock/StockView.swift
import ComposableArchitecture
import SwiftUI

// MARK: - Stock View

struct StockView: View {
    @Bindable var store: StoreOf<StockFeature>

    var body: some View {
        NavigationStack {
            StockListContent(store: store)
                .navigationTitle(String.stock_nav_title)
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $store.searchText, prompt: String.search_stock)
                .toolbar { stockToolbar }
                .overlay {
                    if store.isLoading && store.allStock.isEmpty {
                        LoadingOverlay()
                    }
                }
                .task { store.send(.onLoad) }
                .refreshable { store.send(.forceSync) }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.barcodeScanner,
                action: \.destination.barcodeScanner
            )
        ) { scannerStore in
            BarcodeScannerWrapper(store: scannerStore)
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.checklist,
                action: \.destination.checklist
            )
        ) { checklistStore in
            StockChecklistView(store: checklistStore)
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.product,
                action: \.destination.product
            )
        ) { productStore in
            NavigationStack {
                ProductDetailView(store: productStore)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(
            String.barcode_title,
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.binding(.set(\.errorMessage, nil))) } }
            )
        ) {
            Button("OK") { store.send(.binding(.set(\.errorMessage, nil))) }
        } message: {
            Text(store.errorMessage ?? "")
        }
        // No-op needed: the binding alert above requires BindingAction which StockFeature has.
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var stockToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker(selection: $store.sortField) {
                    Text(String.stock_sort_quantity).tag(StockSortField.quantity)
                    Text(String.stock_sort_code).tag(StockSortField.code)
                    Text(String.stock_sort_name).tag(StockSortField.name)
                } label: { EmptyView() }
                Divider()
                Picker(selection: $store.sortAscending) {
                    Text(String.stock_sort_asc).tag(true)
                    Text(String.stock_sort_desc).tag(false)
                } label: { EmptyView() }
            } label: {
                Image(systemName: "arrow.up.arrow.down").imageScale(.large)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { store.send(.openBarcodeScanner) } label: {
                Image(systemName: "barcode.viewfinder").imageScale(.large)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { store.send(.openChecklist) } label: {
                Image(systemName: "list.bullet.clipboard").imageScale(.large)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SyncDateLabel(isLoading: store.isLoading, lastSyncDate: store.lastSyncDate)
        }
    }
}

// MARK: - Stock List Content

private struct StockListContent: View {
    let store: StoreOf<StockFeature>
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
                                    key: StockScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .global).minY
                                )
                            }
                        )
                }
                Section {
                    ForEach(store.filteredStock) { item in
                        Button {
                            store.send(.openProduct(item))
                        } label: {
                            StockWithPriceRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .onPreferenceChange(StockScrollOffsetPreferenceKey.self) { y in
                withAnimation(.spring(duration: 0.25)) {
                    showScrollToTop = y < 60
                }
            }
            .overlay {
                if store.allStock.isEmpty && !store.isLoading {
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
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                value: "\(store.allStock.count)",
                label: "SKU",
                icon: "shippingbox",
                color: .blue,
                compact: true
            )
            StatCard(
                value: "\(Int(store.totalStockUnits))",
                label: String.stock_units,
                icon: "number.circle",
                color: .green,
                compact: true
            )
            StatCard(
                value: "\(store.lowStockCount)",
                label: String.stock_low,
                icon: "exclamationmark.triangle",
                color: store.lowStockCount > 0 ? .orange : .secondary,
                compact: true
            )
        }
    }
}

// MARK: - Preference Key

private struct StockScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Product Detail View

struct ProductDetailView: View {
    @Bindable var store: StoreOf<ProductDetailFeature>

    var body: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            Section {
                stockRow
                if store.product.sellPriceVAT > 0 { sellPriceRow }
                if store.showPurchaseDetails {
                    purchasePriceRow
                    if let margin = store.product.marginPercent {
                        marginRow(margin)
                    }
                }
                Button {
                    store.send(.togglePurchaseDetails)
                } label: {
                    Label(
                        store.showPurchaseDetails ? String.product_hide_details : String.product_show_details,
                        systemImage: store.showPurchaseDetails ? "eye.slash" : "eye"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(store.product.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.product.code)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(store.product.name)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button { UIPasteboard.general.string = store.product.code } label: {
                Label(String.copy_article, systemImage: "doc.on.doc")
            }
            Button { UIPasteboard.general.string = store.product.name } label: {
                Label(String.copy_name, systemImage: "doc.on.doc")
            }
            Button { UIPasteboard.general.string = "\(store.product.code) \(store.product.name)" } label: {
                Label(String.copy_article_and_name, systemImage: "doc.on.doc")
            }
        }
    }

    private var stockRow: some View {
        let color: Color = store.product.quantity <= 0 ? .red : store.product.quantity <= 2 ? .orange : .green
        return HStack {
            Label(String.product_in_stock, systemImage: "shippingbox")
            Spacer()
            Text(String.sales_quantity(Int(store.product.quantity)))
                .font(.body.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(color.opacity(0.12), in: Capsule())
        }
    }

    private var sellPriceRow: some View {
        HStack {
            Label(String.product_sell_price, systemImage: "tag")
            Spacer()
            Text(czk(store.product.sellPriceVAT)).font(.body.bold())
        }
    }

    private var purchasePriceRow: some View {
        HStack {
            Label(String.product_purchase_price, systemImage: "cart")
            Spacer()
            Text(czk(store.product.purchasePrice)).foregroundStyle(.secondary)
        }
    }

    private func marginRow(_ margin: Double) -> some View {
        let color: Color = margin >= 30 ? .green : margin >= 15 ? .orange : .red
        return HStack {
            Label(String.product_margin, systemImage: "chart.line.uptrend.xyaxis")
            Spacer()
            Text("\(Int(margin))%").font(.body.bold()).foregroundStyle(color)
        }
    }
}

// MARK: - Barcode Scanner Wrapper

struct BarcodeScannerWrapper: View {
    let store: StoreOf<BarcodeScannerFeature>

    var body: some View {
        BarcodeScannerScreen(
            onScan: { barcode in store.send(.scanCompleted(barcode)) },
            onDismiss: { store.send(.dismiss) }
        )
    }
}

// MARK: - Stock Checklist View

struct StockChecklistView: View {
    @Bindable var store: StoreOf<StockChecklistFeature>

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        String.stock_checklist_empty,
                        systemImage: "list.bullet.clipboard"
                    )
                } else {
                    List {
                        ForEach(store.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.callout)
                                    Text(item.code)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 0) {
                                    Button {
                                        store.send(.decrement(item.code))
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)

                                    Text("\(item.quantity)")
                                        .font(.body.bold())
                                        .frame(minWidth: 36)
                                        .multilineTextAlignment(.center)

                                    Button {
                                        store.send(.increment(item.code))
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.green)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String.barcode_title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String.close) { store.send(.dismiss) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.scanTapped)
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if store.totalQuantity > 0 {
                        Text(String.stock_checklist_total(store.totalQuantity))
                            .font(.subheadline.bold())
                    }
                }
            }
            .overlay { if store.isLoading { LoadingOverlay(text: String.barcode_searching) } }
            .task { store.send(.onLoad) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.showScanner },
            set: { if !$0 { store.send(.scannerDismissed) } }
        )) {
            BarcodeScannerScreen(
                onScan: { barcode in store.send(.barcodeScanned(barcode)) },
                onDismiss: { store.send(.scannerDismissed) }
            )
        }
        .alert(
            String.barcode_title,
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.errorDismissed) } }
            )
        ) {
            Button("OK") { store.send(.errorDismissed) }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
