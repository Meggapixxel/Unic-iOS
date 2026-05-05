import SwiftUI

struct FlexiBeeProductDetailView: View {
    let item: FlexiBeeStockWithPrice

    var body: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                stockRow
                if item.sellPriceVAT > 0 { sellPriceRow }
                if item.purchasePrice > 0 { purchasePriceRow }
                if let margin = item.marginPercent { marginRow(margin) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.code)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var stockRow: some View {
        let color: Color = item.quantity <= 0 ? .red : item.quantity <= 2 ? .orange : .green
        return HStack {
            Label(String.product_in_stock, systemImage: "shippingbox")
            Spacer()
            Text("\(Int(item.quantity)) шт")
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
            Text(czk(item.sellPriceVAT))
                .font(.body.bold())
        }
    }

    private var purchasePriceRow: some View {
        HStack {
            Label(String.product_purchase_price, systemImage: "cart")
            Spacer()
            Text(czk(item.purchasePrice))
                .foregroundStyle(.secondary)
        }
    }

    private func marginRow(_ margin: Double) -> some View {
        let color: Color = margin >= 30 ? .green : margin >= 15 ? .orange : .red
        return HStack {
            Label(String.product_margin, systemImage: "chart.line.uptrend.xyaxis")
            Spacer()
            Text("\(Int(margin))%")
                .font(.body.bold())
                .foregroundStyle(color)
        }
    }
}

