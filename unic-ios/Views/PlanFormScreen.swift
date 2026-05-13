import Combine
import SwiftUI

// MARK: - ViewModel

@MainActor
final class PlanFormViewModel: ObservableObject {
    @Published var title: String
    @Published var description: String
    @Published var startDate: Date
    @Published var endDate: Date
    @Published var isSaving = false
    @Published var showAlert = false
    @Published var alertMessage = ""

    let existing: Plan?
    private let onSaved: (Plan) -> Void
    let onDismiss: () -> Void

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(existing: Plan? = nil, onSaved: @escaping (Plan) -> Void, onDismiss: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        title = existing?.title ?? ""
        description = existing?.description ?? ""
        startDate = existing?.startDate ?? Date()
        endDate = existing?.endDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let plan = Plan(
                id: existing?.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: startDate,
                endDate: endDate,
                createdBy: AuthService.shared.currentUser?.id ?? ""
            )
            let saved = try await FirebaseService.shared.savePlan(plan)
            onSaved(saved)
            onDismiss()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

// MARK: - View

struct PlanFormScreen: View {
    @ObservedObject var viewModel: PlanFormViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section(String.section_main) {
                    TextField(String(localized: "plan_title_placeholder"), text: $viewModel.title)
                }
                Section {
                    TextField(String(localized: "plan_description_placeholder"), text: $viewModel.description, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    DatePicker(String(localized: "plan_start_date"), selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker(String(localized: "plan_end_date"), selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: .date)
                }
            }
            .navigationTitle(String(localized: viewModel.existing == nil ? "plan_add" : "plan_edit"))
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
