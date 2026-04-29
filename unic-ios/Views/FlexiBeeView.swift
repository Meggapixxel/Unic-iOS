import SwiftUI

// MARK: - Main FlexiBee View

struct FlexiBeeView: View {
    @StateObject private var viewModel = FlexiBeeViewModel()

    var body: some View {
        NavigationStack {
            StockSectionView(viewModel: viewModel)
                .navigationTitle("FlexiBee")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .searchable(text: $viewModel.searchText, prompt: "Пошук по назві або коду")
                .overlay { if viewModel.isLoading { loadingOverlay } }
                .task { await viewModel.loadIfNeeded() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await viewModel.forceSync() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    HStack(spacing: 6) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(viewModel.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Ніколи")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(viewModel.lastSyncDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Завантаження...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Stock Section

private struct StockSectionView: View {
    @ObservedObject var viewModel: FlexiBeeViewModel

    var body: some View {
        List {
            Section {
                statsRow
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                ForEach(viewModel.filteredStock) { item in
                    StockWithPriceRow(item: item)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.stock.isEmpty && !viewModel.isLoading {
                emptyView("Немає даних по складу")
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            MiniStatsCard(
                value: "\(viewModel.stock.count)",
                label: "SKU",
                icon: "shippingbox",
                color: .blue
            )
            MiniStatsCard(
                value: "\(Int(viewModel.totalStockUnits))",
                label: "Одиниць",
                icon: "number.circle",
                color: .green
            )
            MiniStatsCard(
                value: "\(viewModel.lowStockCount)",
                label: "Мало",
                icon: "exclamationmark.triangle",
                color: viewModel.lowStockCount > 0 ? .orange : .secondary
            )
        }
    }
}

private struct StockWithPriceRow: View {
    let item: FlexiBeeStockWithPrice

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kod)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(item.nazev)
                    .font(.callout)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                quantityBadge
                if item.sellPriceVAT > 0 {
                    priceInfo
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var quantityBadge: some View {
        let color: Color = item.quantity <= 0 ? .red : item.quantity <= 2 ? .orange : .green
        return Text("\(Int(item.quantity)) шт")
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var priceInfo: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(czk(item.sellPriceVAT))
                .font(.caption.bold())
                .foregroundStyle(.primary)
            if let margin = item.marginPercent {
                Text("↑\(Int(margin))%")
                    .font(.caption2)
                    .foregroundStyle(margin >= 30 ? .green : margin >= 15 ? .orange : .red)
            }
        }
    }
}

// MARK: - Shared Components

private struct MiniStatsCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Helpers

private func emptyView(_ message: String) -> some View {
    ContentUnavailableView(message, systemImage: "tray")
}

private func czk(_ amount: Double) -> String {
    guard amount > 0 else { return "—" }
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "CZK"
    fmt.maximumFractionDigits = 0
    return fmt.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) Kč"
}

private func formatAmount(_ amount: Double, currency: String) -> String {
    guard amount > 0 else { return "—" }
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = currency
    fmt.maximumFractionDigits = currency == "CZK" ? 0 : 2
    return fmt.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
}

private func shortAmount(_ amount: Double) -> String {
    if amount >= 1_000_000 { return String(format: "%.1fM", amount / 1_000_000) }
    if amount >= 1_000 { return String(format: "%.0fk", amount / 1_000) }
    return "\(Int(amount))"
}
