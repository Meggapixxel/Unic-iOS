import ComposableArchitecture
import SwiftUI

struct PromosView: View {
    @Bindable var store: StoreOf<PromosFeature>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.displayed) { promo in
                    Button { store.send(.openDetail(promo)) } label: {
                        PromoRowView(promo: promo)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if store.canManagePromos {
                            Button(role: .destructive) {
                                store.send(.deleteTapped(promo))
                            } label: {
                                Label(String.promo_delete, systemImage: "trash")
                            }
                            Button {
                                store.send(.openEdit(promo))
                            } label: {
                                Label(String.promo_edit, systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String.promos_nav_title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if store.canManagePromos {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.send(.openAdd) } label: { Image(systemName: "plus") }
                    }
                }
            }
            .overlay {
                if store.displayed.isEmpty {
                    ContentUnavailableView(String.promos_empty, systemImage: "tag")
                }
            }
            .confirmationDialog(
                String.promo_delete_confirm,
                isPresented: Binding(
                    get: { store.promoToDelete != nil },
                    set: { if !$0 { store.send(.cancelDelete) } }
                ),
                titleVisibility: .visible
            ) {
                Button(String.promo_delete, role: .destructive) { store.send(.deleteConfirmed) }
                Button(String.cancel, role: .cancel) { store.send(.cancelDelete) }
            }
            .sheet(isPresented: Binding(
                get: { store.selectedPromo != nil },
                set: { if !$0 { store.send(.closeDetail) } }
            )) {
                if let promo = store.selectedPromo {
                    PromoDetailView(
                        promo: promo,
                        onEdit: store.canManagePromos ? {
                            store.send(.closeDetail)
                            store.send(.openEdit(promo))
                        } : nil
                    )
                }
            }
            .sheet(
                item: $store.scope(state: \.destination?.form, action: \.destination.form)
            ) { formStore in
                PromoFormView(store: formStore)
            }
            .task { store.send(.onLoad) }
        }
    }
}

// MARK: - Promo Row

private struct PromoRowView: View {
    let promo: PromoOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(promo.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(promo.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(promo.validFrom.formatted(.dateTime.day().month(.abbreviated))) – \(promo.validTo.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Promo Detail

struct PromoDetailView: View {
    let promo: PromoOffer
    let onEdit: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        if promo.isActive {
                            Text("● Active")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1), in: Capsule())
                        }
                        Text(promo.description)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(promo.validFrom.formatted(date: .long, time: .omitted), systemImage: "calendar")
                            .font(.subheadline)
                        Label(promo.validTo.formatted(date: .long, time: .omitted), systemImage: "calendar.badge.checkmark")
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(promo.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton { dismiss() }
                }
                if let onEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onEdit(); dismiss() } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Promo Form

struct PromoFormView: View {
    @Bindable var store: StoreOf<PromoFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String.promo_title_placeholder, text: $store.title)
                }
                Section {
                    TextField(String.promo_description_placeholder, text: $store.description, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    DatePicker(String.promo_valid_from, selection: $store.validFrom, displayedComponents: .date)
                    DatePicker(String.promo_valid_to, selection: $store.validTo, in: store.validFrom..., displayedComponents: .date)
                }
            }
            .navigationTitle(store.existing == nil ? String.promo_add : String.promo_edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { store.send(.dismissAlert) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.send(.saveTapped) } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!store.isValid || store.isSaving)
                }
            }
            .overlay {
                if store.isSaving {
                    ProgressView().padding(8).background(.ultraThinMaterial).cornerRadius(8)
                }
            }
            .alert(String.error, isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { _ in store.send(.dismissAlert) }
            )) {
                Button("OK", role: .cancel) { store.send(.dismissAlert) }
            } message: {
                Text(store.alertMessage ?? "")
            }
        }
    }
}
