import SwiftUI

// MARK: - View

struct StockMovementView: View {
    @StateObject private var viewModel: StockMovementViewModel
    let onDone: () -> Void

    @State private var showProductPicker = false
    @State private var productPickerForItemID: UUID?

    init(pending: PendingMovement, onDone: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: StockMovementViewModel(pending: pending))
        self.onDone = onDone
    }

    var body: some View {
        Form {
            itemsSection
            if let error = viewModel.submitError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle(String.stock_movement_title + " – " + viewModel.invoiceNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String.stock_movement_skip) { viewModel.skip() }
                    .disabled(viewModel.isSubmitting)
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSubmitting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(String.stock_movement_submit) {
                        Task { await viewModel.submit() }
                    }
                    .disabled(!viewModel.isValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showProductPicker) {
            ProductPickerForInvoiceView(priceList: viewModel.priceList) { item in
                guard let itemID = productPickerForItemID,
                      let idx = viewModel.items.firstIndex(where: { $0.id == itemID }) else { return }
                viewModel.items[idx].productCode = item.code
                viewModel.items[idx].productName = item.displayName
            }
        }
        .onChange(of: viewModel.didSucceed) { _, success in
            if success { onDone() }
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        Section {
            ForEach($viewModel.items) { $item in
                MovementItemRow(item: $item) {
                    productPickerForItemID = item.id
                    showProductPicker = true
                }
            }
            .onDelete { viewModel.items.remove(atOffsets: $0) }

            Button {
                viewModel.items.append(StockMovementItemDraft())
            } label: {
                Label(String.stock_movement_add_item, systemImage: "plus.circle.fill")
            }
        } header: {
            Text(String.stock_movement_items)
        }
    }
}

// MARK: - Row

private struct MovementItemRow: View {
    @Binding var item: StockMovementItemDraft
    let onPickProduct: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if item.productName.isEmpty {
                    Text(String.create_invoice_item_name)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.productName)
                        if !item.productCode.isEmpty {
                            Text(item.productCode)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button(action: onPickProduct) {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                Text(String.create_invoice_item_qty + ":")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("1", text: $item.quantity)
                    .keyboardType(.decimalPad)
                    .font(.subheadline)
                    .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
    }
}
