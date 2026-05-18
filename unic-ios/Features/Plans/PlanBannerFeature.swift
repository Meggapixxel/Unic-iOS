import ComposableArchitecture
import Foundation

/// TCA reducer that fetches and exposes the active plan used to drive the floating progress banner
/// overlaid on the main tab interface.
///
/// **Entry point**
/// `MainView` (or the banner host view) dispatches `.load` once, typically on appearance. There is no
/// automatic refresh; the banner reflects a single fetch per session.
///
/// **Key action flows**
/// - `.load` — Sets `isLoading = true` (implicitly via the fetch) and calls
///   `firebaseClient.fetchActivePlan()` asynchronously.
///   - On success → `.loaded(plan?)`: stores the returned plan in state. When `plan` is non-nil,
///     `shouldShow` becomes `true` and the banner becomes visible.
///   - On failure → `.failed`: silently swallowed; banner remains hidden (`plan` stays `nil`).
/// - `.loaded(nil)` — No active plan exists; banner stays hidden.
/// - `.loaded(plan)` — Active plan found; sets `state.plan`, making `shouldShow` return `true`.
///
/// **Navigation**
/// None — this feature has no `Path` or `Destination`. It is a leaf, display-only reducer.
///
/// **Side effects**
/// - `firebaseClient.fetchActivePlan()` — one-shot Firebase read on `.load`; errors are suppressed.
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
