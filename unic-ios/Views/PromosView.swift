import SwiftUI

// MARK: - ViewModel

@MainActor
final class PromosViewModel: ObservableObject {
    @Published var promos: [PromoOffer] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showArchive = false
    @Published var formVM: PromoFormViewModel?
    @Published var selectedPromo: PromoOffer?
    @Published var showDeleteConfirmation = false
    @Published var promoToDelete: PromoOffer?

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    var displayed: [PromoOffer] {
        promos.filter { showArchive ? $0.isPast : !$0.isPast }
    }

    func load() {
        let task = Task {
            isLoading = true
            defer { isLoading = false }
            do {
                promos = try await service.fetchPromos()
            } catch {
                self.error = error.localizedDescription
            }
        }
        tasks.append(task)
    }

    func openAdd() {
        formVM = PromoFormViewModel(
            onSaved: { [weak self] saved in self?.upsert(saved) },
            onDismiss: { [weak self] in self?.formVM = nil }
        )
    }

    func openEdit(_ promo: PromoOffer) {
        formVM = PromoFormViewModel(
            existing: promo,
            onSaved: { [weak self] saved in self?.upsert(saved) },
            onDismiss: { [weak self] in self?.formVM = nil }
        )
    }

    func confirmDelete(_ promo: PromoOffer) {
        promoToDelete = promo
        showDeleteConfirmation = true
    }

    func deletePromo() {
        guard let promo = promoToDelete, let id = promo.id else { return }
        let task = Task {
            do {
                try await service.deletePromo(id: id)
                promos.removeAll { $0.id == id }
            } catch {
                self.error = error.localizedDescription
            }
        }
        tasks.append(task)
    }

    private func upsert(_ promo: PromoOffer) {
        if let idx = promos.firstIndex(where: { $0.id == promo.id }) {
            promos[idx] = promo
        } else {
            promos.insert(promo, at: 0)
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

// MARK: - View

struct PromosScreen: View {
    @StateObject private var viewModel = PromosViewModel()
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.displayed) { promo in
                    Button { viewModel.selectedPromo = promo } label: {
                        PromoRow(promo: promo)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if auth.canManagePromos {
                            Button(role: .destructive) {
                                viewModel.confirmDelete(promo)
                            } label: {
                                Label(String(localized: "promo_delete"), systemImage: "trash")
                            }
                            Button {
                                viewModel.openEdit(promo)
                            } label: {
                                Label(String(localized: "promo_edit"), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "promos_nav_title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: $viewModel.showArchive) {
                        Text(String(localized: "promo_active")).tag(false)
                        Text(String(localized: "promo_archive")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                if auth.canManagePromos {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { viewModel.openAdd() } label: { Image(systemName: "plus") }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial)
                } else if viewModel.displayed.isEmpty {
                    ContentUnavailableView(String(localized: "promos_empty"), systemImage: "tag")
                }
            }
            .confirmationDialog(String(localized: "promo_delete_confirm"), isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
                Button(String(localized: "promo_delete"), role: .destructive) { viewModel.deletePromo() }
                Button(String(localized: "cancel"), role: .cancel) {}
            }
            .sheet(item: $viewModel.selectedPromo) { promo in
                PromoDetailScreen(promo: promo, onEdit: auth.canManagePromos ? { viewModel.openEdit(promo) } : nil)
            }
            .sheet(
                isPresented: Binding(get: { viewModel.formVM != nil }, set: { if !$0 { viewModel.formVM = nil } })
            ) {
                if let formVM = viewModel.formVM {
                    PromoFormScreen(viewModel: formVM)
                }
            }
            .task { viewModel.load() }
            .onDisappear { viewModel.cancel() }
        }
    }
}

// MARK: - Promo Row

private struct PromoRow: View {
    let promo: PromoOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(promo.title)
                    .font(.headline)
                Spacer()
                if promo.isActive {
                    Text("● Active")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
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

// MARK: - Promo Detail View

struct PromoDetailScreen: View {
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

@MainActor
final class PromoFormViewModel: ObservableObject {
    @Published var title: String
    @Published var description: String
    @Published var validFrom: Date
    @Published var validTo: Date
    @Published var isSaving = false
    @Published var showAlert = false
    @Published var alertMessage = ""

    let existing: PromoOffer?
    private let onSaved: (PromoOffer) -> Void
    let onDismiss: () -> Void

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(existing: PromoOffer? = nil, onSaved: @escaping (PromoOffer) -> Void, onDismiss: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        title = existing?.title ?? ""
        description = existing?.description ?? ""
        validFrom = existing?.validFrom ?? Date()
        validTo = existing?.validTo ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let promo = PromoOffer(
                id: existing?.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                validFrom: validFrom,
                validTo: validTo,
                createdBy: AuthService.shared.currentUser?.id ?? ""
            )
            let saved = try await FirebaseService.shared.savePromo(promo)
            onSaved(saved)
            onDismiss()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

struct PromoFormScreen: View {
    @ObservedObject var viewModel: PromoFormViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "promo_title_placeholder"), text: $viewModel.title)
                }
                Section {
                    TextField(String(localized: "promo_description_placeholder"), text: $viewModel.description, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    DatePicker(String(localized: "promo_valid_from"), selection: $viewModel.validFrom, displayedComponents: .date)
                    DatePicker(String(localized: "promo_valid_to"), selection: $viewModel.validTo, in: viewModel.validFrom..., displayedComponents: .date)
                }
            }
            .navigationTitle(String(localized: viewModel.existing == nil ? "promo_add" : "promo_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { viewModel.onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await viewModel.save() } } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving { ProgressView().padding(8).background(.ultraThinMaterial).cornerRadius(8) }
            }
            .alert(String.error, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}
