import SwiftUI

// MARK: - Picker Target

private enum PickerTarget {
    case regularItem(UUID)
    case bundleComponent(sectionId: UUID, itemId: UUID)
}

// MARK: - View

struct StockMovementView: View {
    @StateObject private var viewModel: StockMovementViewModel
    @Binding var isPresented: Bool

    @State private var showProductPicker = false
    @State private var pickerTarget: PickerTarget?

    init(pending: PendingMovement, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: StockMovementViewModel(pending: pending))
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.items.isEmpty || viewModel.bundleSections.isEmpty {
                    regularItemsSection
                }
                ForEach($viewModel.bundleSections) { $section in
                    bundleSectionView(section: $section)
                }
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
