import ComposableArchitecture
import Kingfisher
import SwiftUI

/// Root view for the Promos tab, showing a filterable list of promo offers with swipe actions.
struct PromosView: View {
    @Bindable var store: StoreOf<PromosFeature>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.displayed) { promo in
                    Button { store.send(.openDetail(promo)) } label: {
                        PromoRowView(promo: promo, language: store.language)
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
                                Image(systemName: "pencil")
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
            .safeAreaInset(edge: .bottom) {
                if !store.availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.availableCategories, id: \.self) { cat in
                                FilterChip(
                                    title: cat,
                                    isSelected: store.selectedCategories.contains(cat)
                                ) { store.send(.toggleCategory(cat)) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .glassBackgroundRectangle(cornerRadius: 20)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationInlineTitle(String.promos_nav_title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: Binding(
                        get: { store.language },
                        set: { store.send(.setLanguage($0)) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if store.canManagePromos {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.send(.toggleShowDisabled) } label: {
                            Image(systemName: store.showAll ? "eye" : "eye.slash")
                        }
                        .tint(store.showAll ? .accentColor : .secondary)
                    }
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
            .sheet(
                item: $store.scope(state: \.destination?.detail, action: \.destination.detail)
            ) { detailStore in
                PromoDetailView(store: detailStore)
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

/// List row displaying a promo's localised title, category badge, description preview, and validity period.
private struct PromoRowView: View {
    let promo: PromoOffer
    /// Language used to select the localised title and description.
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlString = promo.imageURL, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .placeholder { Color(.systemGray5) }
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(promo.localizedTitle(for: language))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(promo.category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(promo.isEnabled ? Color.accentColor : Color.gray, in: Capsule())
                }
                let desc = promo.localizedDescription(for: language)
                if !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let vf = promo.validFrom, let vt = promo.validTo {
                    Text(planPeriodString(from: vf, to: vt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(promo.isEnabled ? 1 : 0.45)
    }
}

// MARK: - Promo Detail

/// Full-screen detail sheet for a single promo, showing localised content, status badges, and the validity period visualisation.
struct PromoDetailView: View {
    @Bindable var store: StoreOf<PromoDetailFeature>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let urlString = store.promo.imageURL, let url = URL(string: urlString) {
                        KFImage(url)
                            .resizable()
                            .placeholder {
                                Color(.systemGray5)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                            }
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(store.promo.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                            if store.promo.isActive {
                                Text("● Active")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1), in: Capsule())
                            }
                            if !store.promo.isEnabled {
                                Text("● Disabled")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5), in: Capsule())
                            }
                        }
                        let desc = store.promo.localizedDescription(for: store.language)
                        if !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    if let vf = store.promo.validFrom, let vt = store.promo.validTo {
                        PromoPeriodView(validFrom: vf, validTo: vt)
                    }
                }
                .padding()
            }
            .navigationInlineTitle(store.promo.localizedTitle(for: store.language))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton { store.send(.closeTapped) }
                }
                if store.canManagePromos {
                    ToolbarItem(placement: .topBarTrailing) {
                        if store.isTogglingEnabled {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button { store.send(.toggleEnabled) } label: {
                                Image(systemName: store.promo.isEnabled ? "eye.slash" : "eye")
                            }
                            .tint(store.promo.isEnabled ? .gray : .green)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.send(.editTapped) } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $store.isPickingActivationDates) {
                store.send(.activatePickerDismissed)
            } content: {
                NavigationStack {
                    Form {
                        Section {
                            DatePicker(String.promo_valid_from, selection: $store.activateFrom, displayedComponents: .date)
                            DatePicker(String.promo_valid_to, selection: $store.activateTo, in: store.activateFrom..., displayedComponents: .date)
                        }
                    }
                    .navigationInlineTitle(String.promo_has_dates)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CloseButton { store.send(.activatePickerDismissed) }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button { store.send(.activateDateConfirmed) } label: {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Promo Period

/// Card showing a promo's validity period as a labelled progress bar with a human-readable status string.
private struct PromoPeriodView: View {
    let validFrom: Date
    let validTo: Date

    /// Fraction of the promo's validity period that has elapsed, clamped to `[0, 1]`.
    private var progress: Double {
        let total = validTo.timeIntervalSince(validFrom)
        let elapsed = Date().timeIntervalSince(validFrom)
        return min(max(elapsed / total, 0), 1)
    }

    /// `true` when today falls within the promo's validity window.
    private var isActive: Bool { Date() >= validFrom && Date() <= validTo }

    /// Human-readable countdown or status string (e.g. "3 days left", "Expired").
    private var statusText: String {
        let now = Date()
        if now < validFrom {
            let days = Calendar.current.dateComponents([.day], from: now, to: validFrom).day ?? 0
            return "Starts in \(days) day\(days == 1 ? "" : "s")"
        } else if isActive {
            let days = Calendar.current.dateComponents([.day], from: now, to: validTo).day ?? 0
            return days == 0 ? "Last day" : "\(days) day\(days == 1 ? "" : "s") left"
        } else {
            return "Expired"
        }
    }

    /// Colour of the progress bar: accent when active, orange when upcoming, gray when expired.
    private var barColor: Color {
        if isActive { return .accentColor }
        return Date() < validFrom ? .orange : .gray
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    Text(planDateString(validFrom))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Until").font(.caption).foregroundStyle(.secondary)
                    Text(planDateString(validTo))
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
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Promo Form

/// Modal form for creating or editing a promo offer with per-language sections and a category picker.
struct PromoFormView: View {
    @Bindable var store: StoreOf<PromoFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("English") {
                    TextField("Title", text: $store.titleEn)
                    TextField("Description", text: $store.descriptionEn, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Українська") {
                    TextField("Назва", text: $store.titleUk)
                    TextField("Опис", text: $store.descriptionUk, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Русский") {
                    TextField("Название", text: $store.titleRu)
                    TextField("Описание", text: $store.descriptionRu, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Picker(String.promo_category, selection: $store.category) {
                        ForEach(PromoOffer.categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }
            }
            .navigationInlineTitle(String.promo_add)
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
