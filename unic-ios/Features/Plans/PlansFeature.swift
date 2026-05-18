import ComposableArchitecture
import Foundation

// MARK: - PlansFeature

/// TCA reducer that manages the list of all plans, supporting add, edit, delete, and applying a new plan to all users.
@Reducer
struct PlansFeature {

    // MARK: - Destination

    /// Modal destinations presented from the plans list.
    @Reducer
    enum Destination {
        /// Sheet for creating or editing a plan.
        case form(PlansFormFeature)
    }

    // MARK: - State

    /// State for the plans list screen.
    @ObservableState
    struct State: Equatable {
        /// All fetched plans, sorted newest first.
        var plans: [Plan] = []
        /// Default target values pre-populated in the add-plan form.
        var defaultPlan: DefaultPlan?
        var isLoading = false
        /// Non-nil when a fetch or delete operation has failed.
        var error: String?
        /// Whether the current user is allowed to add, edit, or delete plans.
        var canManagePlans = false
        /// The plan staged for deletion, awaiting user confirmation.
        var pendingDeletePlan: Plan?
        @Presents var destination: Destination.State?
    }

    // MARK: - Action

    /// Actions for the plans list.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Loads permission flags, all plans, and default plan targets from Firebase.
        case onLoad
        case loaded([Plan])
        case defaultPlanLoaded(DefaultPlan?)
        case failed(String)
        /// Opens the add-plan form sheet.
        case addTapped
        /// Opens the form sheet pre-populated with `plan` for editing.
        case editTapped(Plan)
        /// Stages `plan` for deletion and shows the confirmation dialog.
        case deleteTapped(Plan)
        /// Deletes the staged plan from Firebase and removes it locally.
        case deleteConfirmed
        /// Clears the pending-delete state without deleting.
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
                    let dp = try? await firebase.fetchDefaultPlan()
                    await send(.defaultPlanLoaded(dp))
                }

            case .loaded(let plans):
                state.isLoading = false
                state.plans = plans.sorted { $0.startDate > $1.startDate }
                return .none

            case .defaultPlanLoaded(let dp):
                state.defaultPlan = dp
                return .none

            case .failed(let msg):
                state.isLoading = false
                state.error = msg
                return .none

            case .addTapped:
                state.destination = .form(PlansFormFeature.State(defaults: state.defaultPlan))
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
                let isNew = !state.plans.contains(where: { $0.id == plan.id })
                state.destination = nil
                if let idx = state.plans.firstIndex(where: { $0.id == plan.id }) {
                    state.plans[idx] = plan
                } else {
                    state.plans.insert(plan, at: 0)
                }
                guard isNew else { return .none }
                let firebase = firebase
                return .run { [firebase] _ in
                    try? await firebase.setPlanForAllUsers(plan)
                }

            case .binding, .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - PlansFormFeature

/// TCA reducer for the plan create/edit form sheet.
@Reducer
struct PlansFormFeature {
    /// Form state for adding or editing a plan.
    @ObservableState
    struct State: Equatable {
        /// The plan being edited; `nil` means a new plan is being created.
        var existing: Plan?
        var startDate: Date
        var endDate: Date
        var salonsPerDay: Int = 0
        var salonsTotal: Int = 0
        var testDrivesPerDay: Int = 0
        var testDrivesTotal: Int = 0
        var isSaving = false
        /// Non-nil when the save operation has failed.
        var error: String?

        /// Whether the form has a valid date range (end must be after start).
        var isValid: Bool { endDate > startDate }

        /// Initialises the form, preferring values from an existing plan, then defaults, then zero/current-date fallbacks.
        /// - Parameters:
        ///   - existing: The plan to pre-populate for editing; `nil` for a new plan.
        ///   - defaults: Organisation-wide default targets used when creating a new plan.
        init(existing: Plan? = nil, defaults: DefaultPlan? = nil) {
            @Dependency(\.date) var date
            let now = date()
            self.existing = existing
            startDate   = existing?.startDate ?? now
            endDate     = existing?.endDate ?? Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            salonsPerDay     = existing?.targetSalonsPerDay ?? defaults?.targetSalonsPerDay ?? 0
            salonsTotal      = existing?.targetSalons ?? defaults?.targetSalons ?? 0
            testDrivesPerDay = existing?.targetTestDrivesPerDay ?? defaults?.targetTestDrivesPerDay ?? 0
            testDrivesTotal  = existing?.targetTestDrives ?? defaults?.targetTestDrives ?? 0
        }
    }

    /// Actions for the plan form.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Validates the form and persists the plan to Firebase.
        case saveTapped
        /// Emitted after a successful save, carrying the persisted plan back to the parent.
        case saved(Plan)
        case failed(String)
        /// User dismissed the form without saving.
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
                let plan = Plan(
                    id: state.existing?.id,
                    startDate: state.startDate,
                    endDate: state.endDate,
                    createdBy: auth.currentUser()?.id ?? "",
                    targetSalons: state.salonsTotal > 0 ? state.salonsTotal : nil,
                    targetSalonsPerDay: state.salonsPerDay,
                    targetTestDrives: state.testDrivesTotal > 0 ? state.testDrivesTotal : nil,
                    targetTestDrivesPerDay: state.testDrivesPerDay
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
