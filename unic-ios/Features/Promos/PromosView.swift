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
                    .swipeActions(edge: .leading) {
                        if store.canManagePromos {
                            Button {
                                store.send(.toggleEnabled(promo))
                            } label: {
                                Label(
                                    promo.isEnabled ? String.promo_disable : String.promo_enable,
                                    systemImage: promo.isEnabled ? "eye.slash" : "eye"
                                )
                            }
                            .tint(promo.isEnabled ? .gray : .green)
                        }
                    }
                }
            }
            .refreshable { await store.send(.onLoad).finish() }
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
            HStack {
                Text(promo.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(promo.category)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(promo.isEnabled ? Color.accentColor : Color.gray, in: Capsule())
            }
            if !promo.description.isEmpty {
                Text(promo.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(promo.validFrom.formatted(.dateTime.day().month(.abbreviated))) – \(promo.validTo.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(promo.isEnabled ? 1 : 0.45)
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
                        HStack(spacing: 8) {
                            Text(promo.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                            if promo.isActive {
                                Text("● Active")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1), in: Capsule())
                            }
                        }
                        if !promo.description.isEmpty {
                            Text(promo.description)
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    PromoPeriodView(promo: promo)
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

// MARK: - Promo Period

private struct PromoPeriodView: View {
    let promo: PromoOffer

    private var progress: Double {
        let total = promo.validTo.timeIntervalSince(promo.validFrom)
        let elapsed = Date().timeIntervalSince(promo.validFrom)
        return min(max(elapsed / total, 0), 1)
    }

    private var statusText: String {
        let now = Date()
        if now < promo.validFrom {
            let days = Calendar.current.dateComponents([.day], from: now, to: promo.validFrom).day ?? 0
            return "Starts in \(days) day\(days == 1 ? "" : "s")"
        } else if promo.isActive {
            let days = Calendar.current.dateComponents([.day], from: now, to: promo.validTo).day ?? 0
            return days == 0 ? "Last day" : "\(days) day\(days == 1 ? "" : "s") left"
        } else {
            return "Expired"
        }
    }

    private var barColor: Color {
        if promo.isActive { return .accentColor }
        return Date() < promo.validFrom ? .orange : .gray
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    Text(promo.validFrom.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Until").font(.caption).foregroundStyle(.secondary)
                    Text(promo.validTo.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.subheadline.weight(.semibold))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
            HStack {
                Spacer()
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(promo.isActive ? Color.accentColor : .secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                    Picker(String.promo_category, selection: $store.category) {
                        ForEach(PromoOffer.categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
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
                    CloseButton { store.send(.closeTapped) }
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
