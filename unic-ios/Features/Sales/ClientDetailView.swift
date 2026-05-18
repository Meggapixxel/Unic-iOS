// FILE: unic-ios/Features/Sales/ClientDetailView.swift
import ComposableArchitecture
import SwiftUI

/// Detail view for a single FlexiBee client, showing revenue KPIs and the full invoice history.
struct ClientDetailView: View {
    @Bindable var store: StoreOf<ClientDetailFeature>

    var body: some View {
        List {
            headerSection
            statsSection
            invoicesSection
        }
        .listStyle(.insetGrouped)
        .navigationInlineTitle(store.clientName)
        .task { store.send(.onLoad) }
        .toolbar {
            if store.canEditClient {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.editClientTapped)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.createInvoice,
                action: \.destination.createInvoice
            )
        ) { formStore in
            InvoiceFormBridgeView(store: formStore)
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.editClient,
                action: \.destination.editClient
            )
        ) { editStore in
            ClientEditView(store: editStore)
        }
        .safeAreaInset(edge: .bottom) {
            if store.canEdit {
                HStack {
                    Spacer()
                    Button { store.send(.newInvoiceTapped) } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.clientName)
                    .font(.title3.bold())
                if let ic = store.clientIc {
                    Text("IČO: \(ic)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dic = store.clientDic {
                    Text("DIČ: \(dic)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Label("\(store.invoices.count)", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = store.firstOrderDate {
                        Label(first.formatted(date: .abbreviated, time: .omitted), systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = store.lastOrderDate {
                        Label(last.formatted(date: .abbreviated, time: .omitted), systemImage: "clock.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var statsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                KPICard(value: (store.totalRevenue).czk,   label: String.sales_kpi_revenue, icon: "banknote",              color: .blue)
                KPICard(value: (store.paidRevenue).czk,    label: String.sales_kpi_paid,    icon: "checkmark.circle.fill", color: .green)
                KPICard(value: (store.unpaidRevenue).czk,  label: String.sales_kpi_unpaid,  icon: "clock",                 color: .orange)
                KPICard(
                    value: store.overdueCount > 0 ? (store.overdueRevenue).czk : "—",
                    label: String.sales_kpi_overdue,
                    icon: "exclamationmark.circle.fill",
                    color: store.overdueCount > 0 ? .red : .secondary
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var invoicesSection: some View {
        Section(String.sales_invoices) {
            if store.invoices.isEmpty {
                Text(String.sales_invoices_empty)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(store.sortedInvoices) { invoice in
                    Button {
                        store.send(.invoiceTapped(invoice))
                    } label: {
                        InvoiceRowView(invoice: invoice)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Client Edit View

/// Modal form for editing an existing FlexiBee client's name, tax identifiers, email, and phone.
struct ClientEditView: View {
    @Bindable var store: StoreOf<ClientEditFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ClientFormFields(
                        name: $store.name,
                        ic: $store.ic,
                        dic: $store.dic,
                        email: $store.email,
                        phone: $store.phone
                    )
                }
                if let err = store.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationInlineTitle(store.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { store.send(.dismiss) } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(store.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { store.send(.submitTapped) } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!store.isValid)
                    }
                }
            }
        }
    }
}
