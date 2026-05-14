// FILE: unic-ios/Features/Sales/ClientDetailView.swift
import ComposableArchitecture
import SwiftUI

struct ClientDetailView: View {
    @Bindable var store: StoreOf<ClientDetailFeature>

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.clientName)
                        .font(.title3.bold())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        KPICard(
                            value: czk(store.totalRevenue),
                            label: String.sales_kpi_revenue,
                            icon: "banknote",
                            color: .blue
                        )
                        KPICard(
                            value: czk(store.paidRevenue),
                            label: String.sales_kpi_paid,
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section(String.sales_invoices) {
                if store.invoices.isEmpty {
                    Text(String.sales_invoices_empty)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(store.invoices.sorted { ($0.issueDate ?? .distantPast) > ($1.issueDate ?? .distantPast) }) { invoice in
                        Button {
                            store.send(.invoiceTapped(invoice))
                        } label: {
                            InvoiceRowView(invoice: invoice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(store.clientName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
