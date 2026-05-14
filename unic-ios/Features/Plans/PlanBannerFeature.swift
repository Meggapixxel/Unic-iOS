import ComposableArchitecture
import Foundation

@Reducer
struct PlanBannerFeature {
    @ObservableState
    struct State: Equatable {
        var plan: Plan?
        var isLoading = false
        var shouldShow: Bool { plan != nil }
    }

    enum Action {
        case load
        case loaded(Plan?)
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
