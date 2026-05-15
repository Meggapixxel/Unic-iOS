import ComposableArchitecture
import Foundation

// MARK: - PlansFeature

@Reducer
struct PlansFeature {

    // MARK: - Destination

    @Reducer
    enum Destination {
        case form(PlansFormFeature)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var plans: [Plan] = []
        var isLoading = false
        var error: String?
        var canManagePlans = false
        var pendingDeletePlan: Plan?
        @Presents var destination: Destination.State?
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case loaded([Plan])
        case failed(String)
        case addTapped
        case editTapped(Plan)
        case deleteTapped(Plan)
        case deleteConfirmed
        case cancelDelete
        case destination(PresentationAction<Destination.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    // MARK: - Body

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.canManagePlans = auth.canManagePlans()
                state.isLoading = true
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let plans = try await firebase.fetchAllPlans()
                        await send(.loaded(plans))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .loaded(let plans):
                state.isLoading = false
                state.plans = plans.sorted { $0.startDate > $1.startDate }
                return .none

            case .failed(let msg):
                state.isLoading = false
                state.error = msg
                return .none

            case .addTapped:
                state.destination = .form(PlansFormFeature.State())
                return .none

            case .editTapped(let plan):
                state.destination = .form(PlansFormFeature.State(existing: plan))
                return .none

            case .deleteTapped(let plan):
                state.pendingDeletePlan = plan
                return .none

            case .deleteConfirmed:
                guard let plan = state.pendingDeletePlan, let id = plan.id else {
                    state.pendingDeletePlan = nil
                    return .none
                }
                state.plans.removeAll { $0.id == id }
                state.pendingDeletePlan = nil
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        try await firebase.deletePlan(id)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .cancelDelete:
                state.pendingDeletePlan = nil
                return .none

            case .destination(.presented(.form(.saved(let plan)))):
                state.destination = nil
                if let idx = state.plans.firstIndex(where: { $0.id == plan.id }) {
                    state.plans[idx] = plan
                } else {
                    state.plans.insert(plan, at: 0)
                }
                return .none

            case .binding, .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - PlansFormFeature

@Reducer
struct PlansFormFeature {
    @ObservableState
    struct State: Equatable {
        var existing: Plan?
        var title: String
        var description: String
        var startDate: Date
        var endDate: Date
        var targetSalons: Int
        var targetTestDrives: Int
        var isSaving = false
        var error: String?

        var isValid: Bool { endDate > startDate }

        init(existing: Plan? = nil) {
            self.existing = existing
            title = existing?.title ?? ""
            description = existing?.description ?? ""
            startDate = existing?.startDate ?? Date()
            endDate = existing?.endDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            targetSalons = existing?.targetSalons ?? 0
            targetTestDrives = existing?.targetTestDrives ?? 0
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveTapped
        case saved(Plan)
        case failed(String)
        case cancelTapped
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .saveTapped:
                guard state.isValid else { return .none }
                state.isSaving = true
                let trimmedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDesc  = state.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let plan = Plan(
                    id: state.existing?.id,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    startDate: state.startDate,
                    endDate: state.endDate,
                    createdBy: auth.currentUser()?.id ?? "",
                    targetSalons: state.targetSalons > 0 ? state.targetSalons : nil,
                    targetTestDrives: state.targetTestDrives > 0 ? state.targetTestDrives : nil
                )
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let saved = try await firebase.savePlan(plan)
                        await send(.saved(saved))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            case .saved:
                state.isSaving = false
                return .none
            case .failed(let msg):
                state.isSaving = false
                state.error = msg
                return .none
            case .cancelTapped, .binding:
                return .none
            }
        }
    }
}

extension PlansFeature.Destination.State: Equatable {}
