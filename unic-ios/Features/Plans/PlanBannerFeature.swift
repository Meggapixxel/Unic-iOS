import ComposableArchitecture
import Foundation

/// TCA reducer that fetches and exposes the current active plan for the floating plan-progress banner.
@Reducer
struct PlanBannerFeature {
    /// State controlling banner visibility.
    @ObservableState
    struct State: Equatable {
        /// The active plan to display; `nil` means the banner is hidden.
        var plan: Plan?
        var isLoading = false
        /// Whether the banner should be visible; derived from the presence of an active plan.
        var shouldShow: Bool { plan != nil }
    }

    /// Actions for the plan banner lifecycle.
    enum Action {
        /// Triggers a Firebase fetch of the active plan.
        case load
        /// Received once the fetch completes; `nil` indicates no active plan exists.
        case loaded(Plan?)
        /// Fetch failed silently; the banner remains hidden.
        case failed
    }

    @Dependency(\.firebaseClient) var firebase

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let plan = try await firebase.fetchActivePlan()
                        await send(.loaded(plan))
                    } catch {
                        await send(.failed)
                    }
                }
            case .loaded(let plan):
                state.plan = plan
                return .none
            case .failed:
                return .none
            }
        }
    }
}
