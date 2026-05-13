import SwiftUI

// MARK: - CZK Formatter

private extension NumberFormatter {
    static let czk: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "CZK"
        fmt.maximumFractionDigits = 0
        return fmt
    }()
}

func czk(_ amount: Double) -> String {
    guard amount > 0 else { return "—" }
    return NumberFormatter.czk.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) Kč"
}

// MARK: - Sync Date Label

struct SyncDateLabel: View {
    let isLoading: Bool
    let lastSyncDate: Date?

    var body: some View {
        if isLoading {
            ProgressView().scaleEffect(0.8)
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text(lastSyncDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String.never)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(lastSyncDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var text: String = String.loading

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Stat Card (unified KPICard + MiniStatsCard)

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: compact ? 5 : 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .padding(compact ? .vertical : .all, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stock Row

struct StockWithPriceRow: View {
    let item: FlexiBeeStockWithPrice

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.code)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                quantityBadge
                if item.sellPriceVAT > 0 { priceInfo }
            }
        }
        .padding(.vertical, 2)
    }

    private var quantityBadge: some View {
        let color: Color = item.quantity <= 0 ? .red : item.quantity <= 2 ? .orange : .green
        return Text(String.sales_quantity(Int(item.quantity)))
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var priceInfo: some View {
        Text(czk(item.sellPriceVAT))
            .font(.caption.bold())
            .foregroundStyle(.primary)
    }
}
