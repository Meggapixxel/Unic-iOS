import ComposableArchitecture
import Foundation

// MARK: - PlansFeature

/// TCA reducer that manages the plans list screen, supporting full CRUD (create, edit, delete) of plan
/// documents in Firebase, and automatically propagating a newly created plan to all users.
///
/// **Entry point**
/// `PlansView` dispatches `.onLoad` on appearance. `.onLoad` resolves the `canManagePlans` permission
/// flag synchronously, then fetches all plans and the organisation-wide default plan targets from Firebase.
///
/// **Key action flows**
/// - `.onLoad` — Sets `isLoading = true`, resolves `canManagePlans` from `authClient`, then runs a single
///   `Effect.run` that:
///   1. `firebase.fetchAllPlans()` → `.loaded(plans)` (or `.failed` on error).
///   2. `firebase.fetchDefaultPlan()` → `.defaultPlanLoaded(dp?)` (failure is silently ignored).
/// - `.loaded(plans)` — Clears loading flag, stores plans sorted newest-first by `startDate`.
/// - `.defaultPlanLoaded(dp)` — Stores default targets used to pre-populate the add-plan form.
/// - `.addTapped` — Presents the `.form` sheet with `PlansFormFeature.State(defaults:)` (blank form
///   seeded with default targets).
/// - `.editTapped(plan)` — Presents the `.form` sheet with `PlansFormFeature.State(existing:)` (form
///   pre-populated from the selected plan).
/// - `.deleteTapped(plan)` — Stages `plan` in `pendingDeletePlan`; the view shows a confirmation dialog.
/// - `.deleteConfirmed` — Optimistically removes the plan from the local array, clears `pendingDeletePlan`,
///   then calls `firebase.deletePlan(id)` asynchronously. On failure, sends `.failed`.
/// - `.cancelDelete` — Clears `pendingDeletePlan` without deleting.
/// - `.destination(.presented(.form(.saved(plan))))` — Form sheet dismissed after a successful save.
///   Upserts the plan locally (prepends if new, replaces in-place if editing). Always calls
///   `firebase.setPlanForAllUsers(plan)` to propagate the plan (create or edit) to every user.
///
/// **Navigation (`Destination`)**
/// Uses a single `@Presents` destination:
/// - `.form(PlansFormFeature)` — A sheet for creating or editing a plan. Dismissed automatically by
///   setting `destination = nil` when `.saved` is received.
///
/// **Side effects**
/// - `firebase.fetchAllPlans()` — Firebase collection read on `.onLoad`.
/// - `firebase.fetchDefaultPlan()` — Firebase document read on `.onLoad`; failure is suppressed.
/// - `firebase.deletePlan(id)` — Firebase document deletion on `.deleteConfirmed`.
/// - `firebase.savePlan(plan)` — Firebase write inside `PlansFormFeature` on `.saveTapped`.
/// - `firebase.setPlanForAllUsers(plan)` — Firebase batch write triggered after every plan save (create or edit);
///   propagates the plan to every user document. Errors are silently ignored.
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
                state.destination = nil
                if let idx = state.plans.firstIndex(where: { $0.id == plan.id }) {
                    state.plans[idx] = plan
                } else {
                    state.plans.insert(plan, at: 0)
                }
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

/// TCA reducer for the plan create/edit form sheet presented modally from `PlansFeature`.
///
/// **Entry point**
/// Instantiated by `PlansFeature` on `.addTapped` or `.editTapped`. Initial state is populated in
/// `init(existing:defaults:)` — either from an existing `Plan` (edit mode) or from `DefaultPlan`
/// targets (create mode), with zero/current-date fallbacks when neither is available.
///
/// **Key action flows**
/// - `.binding` — `BindingReducer` keeps `startDate`, `endDate`, and target numeric fields in sync
///   with the form controls. `isValid` is derived: `endDate > startDate`.
/// - `.saveTapped` — Guards `isValid`, sets `isSaving = true`, constructs a `Plan` value (reusing the
///   existing `id` for edits, `nil` for new), then calls `firebase.savePlan(_:)` asynchronously.
///   - On success → `.saved(plan)`: clears `isSaving`; the parent `PlansFeature` receives
///     `.destination(.presented(.form(.saved(plan))))` and handles the upsert + user propagation.
///   - On failure → `.failed(msg)`: clears `isSaving`, sets `error` for display.
/// - `.cancelTapped` — No state change; the parent dismisses the sheet via `@Presents` machinery.
///
/// **Navigation**
/// None — this is a leaf form reducer with no stack or sub-destinations.
///
/// **Side effects**
/// - `firebase.savePlan(_:)` — Firebase write (create or update) executed on `.saveTapped`.
@Reducer
struct PlansFormFeature {
    /// Form state for adding or editing a plan.
    @ObservableState
    struct State: Equatable {
        /// The plan being edited; `nil` means a new plan is being created.
        var existing: Plan?
        /// `true` when the form was opened with an existing plan (edit mode).
        var isEditing: Bool
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
            self.isEditing = existing != nil
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
    @Dependency(\.dismiss) var dismiss

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
            case .cancelTapped:
                return .run { _ in await dismiss() }
            case .binding:
                return .none
            }
        }
    }
}

extension PlansFeature.Destination.State: Equatable {}
