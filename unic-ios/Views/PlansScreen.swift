import Combine
import SwiftUI

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var plans: [Plan] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var formVM: PlanFormViewModel?
    @Published var showDeleteConfirmation = false
    @Published var planToDelete: Plan?

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    func load() {
        let task = Task {
            isLoading = true
            defer { isLoading = false }
            do {
                plans = try await service.fetchAllPlans()
            } catch {
                self.error = error.localizedDescription
            }
        }
        tasks.append(task)
    }

    func openAdd() {
        formVM = PlanFormViewModel(
            onSaved: { [weak self] saved in self?.upsert(saved) },
            onDismiss: { [weak self] in self?.formVM = nil }
        )
    }

    func openEdit(_ plan: Plan) {
        formVM = PlanFormViewModel(
            existing: plan,
            onSaved: { [weak self] saved in self?.upsert(saved) },
            onDismiss: { [weak self] in self?.formVM = nil }
        )
    }

    func confirmDelete(_ plan: Plan) {
        planToDelete = plan
        showDeleteConfirmation = true
    }

    func deletePlan() {
        guard let plan = planToDelete, let id = plan.id else { return }
        let task = Task {
            do {
                try await service.deletePlan(id: id)
                plans.removeAll { $0.id == id }
            } catch {
                self.error = error.localizedDescription
            }
        }
        tasks.append(task)
    }

    private func upsert(_ plan: Plan) {
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else {
            plans.insert(plan, at: 0)
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

struct PlansScreen: View {
    @StateObject private var viewModel = PlansViewModel()
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        List {
            ForEach(viewModel.plans) { plan in
                PlanRow(plan: plan)
                    .swipeActions(edge: .trailing) {
                        if auth.canManagePlans {
                            Button(role: .destructive) {
                                viewModel.confirmDelete(plan)
                            } label: {
                                Label(String(localized: "plan_delete"), systemImage: "trash")
                            }
                            Button {
                                viewModel.openEdit(plan)
                            } label: {
                                Label(String(localized: "plan_edit"), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "plans_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.canManagePlans {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.openAdd() } label: { Image(systemName: "plus") }
                }
            }
        }
        .overlay {
            if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) }
            if !viewModel.isLoading && viewModel.plans.isEmpty {
                ContentUnavailableView(String(localized: "plans_empty"), systemImage: "target")
            }
        }
        .confirmationDialog(String(localized: "plan_delete_confirm"), isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
            Button(String(localized: "plan_delete"), role: .destructive) { viewModel.deletePlan() }
            Button(String(localized: "cancel"), role: .cancel) {}
        }
        .sheet(
            isPresented: Binding(get: { viewModel.formVM != nil }, set: { if !$0 { viewModel.formVM = nil } })
        ) {
            if let formVM = viewModel.formVM {
                PlanFormScreen(viewModel: formVM)
            }
        }
        .task { viewModel.load() }
        .onDisappear { viewModel.cancel() }
    }
}

private struct PlanRow: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.title)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            Text(plan.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(plan.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(plan.endDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if plan.isActive {
            Text("● Active")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else if plan.isPast {
            Text("✓ Done")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("◌ Upcoming")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
