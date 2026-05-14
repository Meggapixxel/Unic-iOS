// FILE: unic-ios/Features/Sales/ClientDetailView.swift
import ComposableArchitecture
import SwiftUI

struct ClientDetailView: View {
    @Bindable var store: StoreOf<ClientDetailFeature>

    var body: some View {
        List {
            headerSection
            statsSection
            invoicesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(store.clientName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canEditClient {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String.edit_client) {
                        store.send(.editClientTapped)
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
                if let code = store.clientCode {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
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
                KPICard(value: czk(store.totalRevenue),   label: String.sales_kpi_revenue, icon: "banknote",              color: .blue)
                KPICard(value: czk(store.paidRevenue),    label: String.sales_kpi_paid,    icon: "checkmark.circle.fill", color: .green)
                KPICard(value: czk(store.unpaidRevenue),  label: String.sales_kpi_unpaid,  icon: "clock",                 color: .orange)
                KPICard(
                    value: store.overdueCount > 0 ? czk(store.overdueRevenue) : "—",
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

struct ClientEditView: View {
    @Bindable var store: StoreOf<ClientEditFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(String.create_invoice_client) {
                    TextField(String.create_client_name_placeholder, text: $store.name)
                        .autocorrectionDisabled()
                }
                Section("IČO / DIČ") {
                    LabeledContent("IČO") {
                        TextField("12345678", text: $store.ic)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("DIČ") {
                        TextField("CZ12345678", text: $store.dic)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }
                Section(String.section_contacts) {
                    LabeledContent("Email") {
                        TextField("info@company.cz", text: $store.email)
                            .keyboardType(.emailAddress)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent(String.phone_label) {
                        TextField("+420 123 456 789", text: $store.phone)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
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
            .navigationTitle(String.edit_client)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.cancel) { store.send(.dismiss) }
                        .disabled(store.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(String.save) { store.send(.submitTapped) }
                            .disabled(!store.isValid)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}
