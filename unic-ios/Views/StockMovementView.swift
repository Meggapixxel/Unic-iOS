import SwiftUI
import Combine

// MARK: - Draft Model

struct StockMovementLineDraft: Identifiable {
    let id = UUID()
    var name:      String
    var productCode: String
    var quantity:  String

    var quantityDouble: Double { Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    var isValid: Bool { !productCode.trimmingCharacters(in: .whitespaces).isEmpty && quantityDouble > 0 }

    func toNewLine() -> NewStockMovementLine? {
        guard isValid else { return nil }
        return NewStockMovementLine(productCode: "code:\(productCode.trimmingCharacters(in: .whitespaces))", quantity: quantityDouble)
    }
}

// MARK: - ViewModel

@MainActor
final class StockMovementFormViewModel: ObservableObject {
    @Published var lines: [StockMovementLineDraft]
    @Published var notes: String
    @Published private(set) var isSubmitting = false
    @Published private(set) var error: String?
    @Published private(set) var didSucceed = false

    init(invoice: FlexiBeeInvoice, lineItems: [FlexiBeeInvoiceItem]) {
        self.notes = "Výdej k faktuře \(invoice.invoiceNumber)"
        let drafts = lineItems
            .filter { !$0.productCode.isEmpty && $0.quantity > 0 }
            .map { item in
                StockMovementLineDraft(
                    name:      item.productName,
                    productCode: item.productCode,
                    quantity:  String(format: "%g", item.quantity)
                )
            }
        self.lines = drafts.isEmpty ? [StockMovementLineDraft(name: "", productCode: "", quantity: "1")] : drafts
    }

    var isValid: Bool { lines.contains { $0.isValid } }

    func submit() async {
        guard isValid else { return }
        isSubmitting = true
        error = nil
        let validLines = lines.compactMap { $0.toNewLine() }
        do {
            let movement = NewStockMovement(
                documentType: "code:VYDEJ",
                description:  notes.isEmpty ? nil : notes,
                lines:        validLines
            )
            try await FlexiBeeService.shared.createStockMovement(movement)
            didSucceed = true
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - View

struct StockMovementFormView: View {
    @StateObject var viewModel: StockMovementFormViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                linesSection
                notesSection
                if let err = viewModel.error {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String.stock_movement_title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { dismiss() }
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
            .onChange(of: viewModel.didSucceed) { _, success in
                if success { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var linesSection: some View {
        Section {
            ForEach($viewModel.lines) { $line in
                StockMovementLineRow(line: $line)
            }
            .onDelete { viewModel.lines.remove(atOffsets: $0) }

            Button {
                viewModel.lines.append(StockMovementLineDraft(name: "", productCode: "", quantity: "1"))
            } label: {
                Label(String.stock_movement_add_item, systemImage: "plus.circle.fill")
            }
        } header: {
            Text(String.stock_movement_items)
        }
    }

    private var notesSection: some View {
        Section(String.create_invoice_notes) {
            TextField(String.create_invoice_notes_placeholder, text: $viewModel.notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }
}

// MARK: - Line Row

private struct StockMovementLineRow: View {
    @Binding var line: StockMovementLineDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !line.name.isEmpty {
                Text(line.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String.stock_movement_code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("CFB/220", text: $line.productCode)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(String.create_invoice_item_qty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("1", text: $line.quantity)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .frame(width: 60)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
