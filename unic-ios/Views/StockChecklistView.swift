import SwiftUI

struct StockChecklistScreen: View {
    @StateObject private var viewModel = StockChecklistViewModel()

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                ChecklistItemRow(item: item, viewModel: viewModel)
            }
            .onDelete { indexSet in
                viewModel.items.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.plain)
        .navigationTitle(String.stock_checklist_total(viewModel.totalQuantity))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: viewModel.jsonPayload) {
                    Image(systemName: "square.and.arrow.up").imageScale(.large)
                }
                .disabled(viewModel.items.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { viewModel.showScanner = true } label: {
                    Image(systemName: "barcode.viewfinder").imageScale(.large)
                }
            }
        }
        .overlay {
            if viewModel.isSearchingBarcode {
                LoadingOverlay(text: String.barcode_searching)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    String.stock_checklist_empty,
                    systemImage: "list.bullet.clipboard"
                )
            }
        }
        .fullScreenCover(isPresented: $viewModel.showScanner) {
            BarcodeScannerScreen(
                onScan: { barcode in Task { await viewModel.handleScannedBarcode(barcode) } },
                onDismiss: { viewModel.showScanner = false }
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
        .task { await viewModel.loadIfNeeded() }
    }
}

// MARK: - Row

private struct ChecklistItemRow: View {
    let item: ChecklistItem
    let viewModel: StockChecklistViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name)
                    .font(.body)
                Text(item.product.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    viewModel.decrement(item)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Text("\(item.quantity)")
                    .monospacedDigit()
                    .frame(minWidth: 32, alignment: .center)
                    .font(.body.weight(.semibold))

                Button {
                    viewModel.increment(item)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
