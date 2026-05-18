import SwiftUI

// MARK: - Picker Target

/// Identifies which item the product picker was triggered for, distinguishing regular rows from bundle components.
private enum PickerTarget {
    /// A regular (non-bundle) movement item identified by its draft `id`.
    case regularItem(UUID)
    /// A component within a bundle section, identified by section and item IDs.
    case bundleComponent(sectionId: UUID, itemId: UUID)
}

// MARK: - View

/// Form screen for creating a stock movement tied to an invoice, driven by `StockMovementViewModel`.
/// Displays regular item rows and optional bundle sections, with a product picker sheet.
struct StockMovementScreen: View {
    @StateObject private var viewModel: StockMovementViewModel
    @Binding var isPresented: Bool

    @State private var showProductPicker = false
    @State private var pickerTarget: PickerTarget?

    /// Convenience initializer that creates a `StockMovementViewModel` from a `PendingMovement`.
    init(pending: PendingMovement, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: StockMovementViewModel(pending: pending))
        self._isPresented = isPresented
    }

    /// Initializer used by `StockMovementBridgeView` (TCA), which pre-builds the view model.
    init(viewModel: StockMovementViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($viewModel.bundleSections) { $section in
                    bundleSectionView(section: $section)
                }
                if !viewModel.items.isEmpty || viewModel.bundleSections.isEmpty {
                    regularItemsSection
                }
                if let error = viewModel.submitError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationInlineTitle(String.stock_movement_title + " – " + viewModel.invoiceNumber)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { viewModel.skip() } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button {
                            Task { await viewModel.submit() }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!viewModel.isValid)
                    }
                }
            }
            .sheet(isPresented: $showProductPicker) {
                ProductPickerForInvoiceView(priceList: viewModel.priceList, onSelect: { item in
                    handleProductPicked(item)
                }, isPresented: $showProductPicker)
            }
            .onChange(of: viewModel.didSucceed) { _, success in
                if success { isPresented = false }
            }
        }
    }

    // MARK: - Product Picker Handler

    /// Updates the correct item when a product is selected from the picker, based on `pickerTarget`.
    private func handleProductPicked(_ item: FlexiBeeCenikItem) {
        guard let target = pickerTarget else { return }
        switch target {
        case .regularItem(let id):
            guard let idx = viewModel.items.firstIndex(where: { $0.id == id }) else { return }
            viewModel.items[idx].productCode = item.code
            viewModel.items[idx].productName = item.displayName

        case .bundleComponent(let sId, let iId):
            guard let sIdx = viewModel.bundleSections.firstIndex(where: { $0.id == sId }),
                  let iIdx = viewModel.bundleSections[sIdx].components.firstIndex(where: { $0.id == iId }) else { return }
            viewModel.bundleSections[sIdx].components[iIdx].productCode = item.code
            viewModel.bundleSections[sIdx].components[iIdx].productName = item.displayName
        }
    }

    // MARK: - Regular Items Section

    private var regularItemsSection: some View {
        Section {
            ForEach($viewModel.items) { $item in
                MovementItemRow(item: $item) {
                    pickerTarget = .regularItem(item.id)
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

    // MARK: - Bundle Section

    @ViewBuilder
    private func bundleSectionView(section: Binding<BundleSection>) -> some View {
        Section {
            ForEach(section.components) { $component in
                MovementItemRow(item: $component) {
                    pickerTarget = .bundleComponent(sectionId: section.wrappedValue.id, itemId: component.id)
                    showProductPicker = true
                }
            }
            .onDelete { viewModel.removeBundleComponent(from: section.wrappedValue.id, at: $0) }

            Button {
                if let newId = viewModel.addBundleComponent(to: section.wrappedValue.id) {
                    pickerTarget = .bundleComponent(sectionId: section.wrappedValue.id, itemId: newId)
                    showProductPicker = true
                }
            } label: {
                Label(String.stock_movement_add_item, systemImage: "plus.circle.fill")
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.orange)
                Text(section.wrappedValue.bundleName)
            }
        }
    }
}

// MARK: - Row

/// Editable row for a single stock-movement item showing the product name, code, and quantity field.
private struct MovementItemRow: View {
    @Binding var item: StockMovementItemDraft
    /// Called when the user taps the product-search button to open the picker.
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
