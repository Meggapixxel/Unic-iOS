import ComposableArchitecture
import Foundation

/// Manages the user-activity screen, showing a horizontally pageable timeline of plan periods.
/// Each page displays rings, status counts, and a day-by-day timeline for one plan period.
/// Tapping the plan header opens the edit form when the user has `canManagePlans` permission.
///
/// **Entry point**
/// `.onLoad` is dispatched by the view's `.task`. It resolves permissions, then fetches activity
/// entries and plan periods concurrently.
///
/// **Key action flows**
/// - `.onLoad` — resolves `canManagePlans`, sets `isLoading = true`, fires two concurrent requests:
///   1. `firebase.fetchUserActivity(userId)` → `.loaded`.
///   2. `firebase.fetchAllPlanPeriods(userId)` → `.planPeriodsLoaded`.
/// - `.loaded(_)` — stores entries sorted newest-first; clears `isLoading`.
/// - `.planPeriodsLoaded(_)` — stores plan periods; `entriesByPlan` recomputes automatically.
/// - `.editPlanTapped(period)` — converts `PlanPeriod` to `Plan` and presents the edit form sheet.
/// - `.destination(.presented(.editPlan(.saved(plan))))` — updates the local plan period and
///   calls `firebase.setPlanForAllUsers` to propagate the change.
/// - `.deleteConfirmed(_)` — removes entry optimistically, then calls `firebase.deleteActivityEntry`.
@Reducer
struct UserActivityFeature {

    // MARK: - Destination

    @Reducer
    enum Destination {
        case editPlan(PlansFormFeature)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var user: AppUser
        var entries: [UserActivityEntry] = []
        var planPeriods: [PlanPeriod] = []
        var selectedPlanIndex: Int = 0
        var isLoading = false
        var error: String?
        var canDeleteActivity = false
        var canManagePlans = false
        @Presents var destination: Destination.State?

        init(user: AppUser) {
            self.user = user
        }

        /// Activity entries split by plan period, parallel to `planPeriods`.
        var entriesByPlan: [[UserActivityEntry]] {
            planPeriods.map { period in
                entries
                    .filter { $0.timestamp >= period.startDate && $0.timestamp <= period.endDate }
                    .sorted { $0.timestamp > $1.timestamp }
            }
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case loaded([UserActivityEntry])
        case planPeriodsLoaded([PlanPeriod])
        case failed(String)
        case editPlanTapped(PlanPeriod)
        case deleteConfirmed(UserActivityEntry)
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
            case .binding:
                return .none

            case .onLoad:
                state.canDeleteActivity = auth.canDeleteActivity()
                state.canManagePlans = auth.canManagePlans()
                state.isLoading = true
                let userId = state.user.id
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let entries = try await firebase.fetchUserActivity(userId)
                        await send(.loaded(entries))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                    let periods = (try? await firebase.fetchAllPlanPeriods(userId)) ?? []
                    await send(.planPeriodsLoaded(periods))
                }

            case .loaded(let entries):
                state.isLoading = false
                state.entries = entries.sorted { $0.timestamp > $1.timestamp }
                return .none

            case .planPeriodsLoaded(let periods):
                state.planPeriods = periods
                return .none

            case .failed(let msg):
                state.isLoading = false
                state.error = msg
                return .none

            case .editPlanTapped(let period):
                guard state.canManagePlans else { return .none }
                let plan = Plan(
                    id: period.id,
                    startDate: period.startDate,
                    endDate: period.endDate,
                    createdBy: auth.currentUser()?.id ?? "",
                    targetSalons: period.targetSalons,
                    targetSalonsPerDay: period.targetSalonsPerDay,
                    targetTestDrives: period.targetTestDrives,
                    targetTestDrivesPerDay: period.targetTestDrivesPerDay
                )
                state.destination = .editPlan(PlansFormFeature.State(existing: plan))
                return .none

            case .destination(.presented(.editPlan(.saved(let plan)))):
                state.destination = nil
                if let idx = state.planPeriods.firstIndex(where: { $0.id == (plan.id ?? "") }) {
                    let old = state.planPeriods[idx]
                    state.planPeriods[idx] = PlanPeriod(
                        id: plan.id ?? old.id,
                        startDate: plan.startDate,
                        endDate: plan.endDate,
                        targetSalons: plan.targetSalons,
                        targetSalonsPerDay: plan.targetSalonsPerDay,
                        targetTestDrives: plan.targetTestDrives,
                        targetTestDrivesPerDay: plan.targetTestDrivesPerDay,
                        result: old.result
                    )
                }
                let firebase = firebase
                return .run { [firebase] _ in
                    try? await firebase.setPlanForAllUsers(plan)
                }

            case .deleteConfirmed(let entry):
                state.entries.removeAll { $0.id == entry.id }
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        try await firebase.deleteActivityEntry(entry)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension UserActivityFeature.Destination.State: Equatable {}
