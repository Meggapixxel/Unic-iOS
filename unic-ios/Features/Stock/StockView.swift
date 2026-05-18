// FILE: unic-ios/Features/Stock/StockView.swift
import ComposableArchitecture
import SwiftUI

// MARK: - Stock View

/// Root view for the Stock tab. Hosts a `NavigationStack` with search, sort, barcode scanning,
/// checklist sheet, and drill-down to product detail or catalog.
struct StockView: View {
    @Bindable var store: StoreOf<StockFeature>

    var body: some View {
        StockListContent(store: store)
            .searchable(text: $store.searchText, prompt: String.search_stock)
            .overlay {
                if store.isLoading && store.allStock.isEmpty {
                    LoadingOverlay()
                }
            }
            .task { store.send(.onLoad) }
            .refreshable { store.send(.forceSync) }
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
    }

    // MARK: - Toolbar (internal — reused by TabChildView extension)

    @ToolbarContentBuilder
    fileprivate var stockToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker(selection: $store.sortField) {
                    Text(String.stock_sort_section).tag(StockSortField.section)
                    Text(String.stock_sort_name).tag(StockSortField.name)
                    Text(String.stock_sort_quantity).tag(StockSortField.quantity)
                } label: { EmptyView() }
                if store.sortField == .quantity {
                    Divider()
                    Picker(selection: $store.sortAscending) {
                        Text(String.stock_sort_asc).tag(true)
                        Text(String.stock_sort_desc).tag(false)
                    } label: { EmptyView() }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").imageScale(.large)
            }
        }
        
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 16) {
                Button { store.send(.openBarcodeScanner) } label: {
                    Image(systemName: "barcode.viewfinder").imageScale(.large)
                }
                Button { store.send(.openChecklist) } label: {
                    Image(systemName: "list.bullet.clipboard").imageScale(.large)
                }
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if store.sortField == .section {
                    Button {
                        let allLines = store.groupedStock.map(\.line)
                        if store.collapsedSections.count == allLines.count {
                            store.send(.expandAll)
                        } else {
                            store.send(.collapseAll(allLines))
                        }
                    } label: {
                        Image(systemName: store.collapsedSections.count == store.groupedStock.count
                              ? "rectangle.expand.vertical"
                              : "rectangle.compress.vertical")
                            .imageScale(.large)
                    }
                }
                Button { store.send(.openCatalog) } label: {
                    Image(systemName: "book.pages").imageScale(.large)
                }
            }
        }
    }
}

// MARK: - TabChildView

extension StockView: TabChildView {
    var tabTitle: String { String.stock_nav_title }

    @ToolbarContentBuilder var tabToolbar: some ToolbarContent {
        stockToolbar
    }
}

// MARK: - Stock List Content

/// Internal view that renders the scrollable stock list with grouped sections, stats header,
/// and a floating scroll-to-top button.
private struct StockListContent: View {
    let store: StoreOf<StockFeature>
    @State private var showScrollToTop = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if store.sortField == .section {
                    ForEach(store.groupedStock, id: \.line) { group in
                        Section(isExpanded: Binding(
                            get: { !store.collapsedSections.contains(group.line) },
                            set: { _ in store.send(.toggleSection(group.line)) }
                        )) {
                            ForEach(group.items) { item in
                                stockItemButton(item)
                            }
                        } header: {
                            let collapsed = store.collapsedSections.contains(group.line)
                            HStack(spacing: 4) {
                                Text("\(group.line) (\(group.items.count))")
                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                                    .animation(.easeInOut(duration: 0.2), value: collapsed)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassBackgroundCapsule()
                            .textCase(nil)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { store.send(.toggleSection(group.line)) }
                        }
                    }
                } else {
                    Section {
                        ForEach(store.filteredStock) { item in
                            stockItemButton(item)
                        }
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
    
    /// Returns a tappable row for a single stock item that navigates to its detail screen.
    private func stockItemButton(_ item: FlexiBeeStockItem) -> some View {
        Button { store.send(.openProduct(item)) } label: {
            HStack(spacing: 8) {
                StockWithPriceRow(item: item)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack {
            SyncStatusRow(isLoading: false, lastSyncDate: store.lastSyncDate)
                
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
}

// MARK: - Preference Key

/// Tracks the vertical scroll offset of the stock list to show or hide the scroll-to-top button.
private struct StockScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Product Detail View

/// Displays full details for a single stock item including quantity, sell price, and optionally purchase price.
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
        .navigationInlineTitle(store.product.code)
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
            Text((store.product.sellPriceVAT).czk).font(.body.bold())
        }
    }

    private var purchasePriceRow: some View {
        HStack {
            Label(String.product_purchase_price, systemImage: "cart")
            Spacer()
            Text(store.product.formattedPurchasePrice).foregroundStyle(.secondary)
        }
    }

}

// MARK: - Barcode Scanner Wrapper

/// Wraps the UIKit `BarcodeScannerScreen` to bridge scan and dismiss events into TCA actions.
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

/// Modal sheet view for performing a physical stock count via barcode scanner with +/- quantity controls.
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
            .navigationInlineTitle(String.barcode_title)
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
