import ComposableArchitecture
import Foundation

/// TCA reducer for the post-login splash/loading screen that preloads salon data and enforces a minimum
/// display duration before handing control to `MainFeature`.
///
/// **Entry point**
/// Activated by `AppFeature` when `.authStateChanged(user)` fires and the app is not already in `.main`.
/// `WelcomeView` dispatches `.onAppear`, which kicks off two parallel effects.
///
/// **Key action flows**
/// - `.onAppear` — Fires two concurrent `Effect.run` tasks via `.merge`:
///   1. **Data fetch** — calls `firebaseClient.fetchAllSalons()`. On success → `.dataLoaded(salons)`;
///      on failure → `.dataFailed` (proceeds with an empty list so the app is never blocked).
///   2. **Minimum timer** — sleeps for 1 second via `continuousClock`, then fires `.minTimeElapsed`.
/// - `.dataLoaded(salons)` — Stores salons in state, sets `isDataReady = true`. If `canProceed` is also
///   true, immediately sends `.delegate(.readyToEnter)`.
/// - `.dataFailed` — Sets `isDataReady = true` with an empty salon list. Same `canProceed` check.
/// - `.minTimeElapsed` — Sets `minTimePassed = true`. Same `canProceed` check.
/// - `.delegate(.readyToEnter(user, salons))` — Surfaced to `AppFeature`, which transitions the app to
///   `.main(MainFeature.State(currentUser:preloadedSalons:))`.
///
/// **Navigation**
/// No internal navigation stack. Transition out is driven exclusively via the `.delegate` action to the
/// parent `AppFeature`.
///
/// **Side effects**
/// - `firebaseClient.fetchAllSalons()` — one-shot Firebase read; result is handed off to `MainFeature`.
/// - `continuousClock.sleep(for: .seconds(1))` — guarantees a minimum splash display time.
@Reducer
struct WelcomeFeature {
    /// State for the welcome/loading phase.
    @ObservableState
    struct State: Equatable {
        /// The freshly authenticated user shown in the greeting.
        let user: AppUser
        /// Salons fetched in the background to hand off to ``MainFeature``.
        var salons: IdentifiedArrayOf<Salon> = []
        /// True once the Firebase fetch has completed (success or failure).
        var isDataReady = false
        /// True once the minimum splash display time has elapsed.
        var minTimePassed = false

        /// Whether both data and minimum display time are satisfied, allowing entry to the main screen.
        var canProceed: Bool { isDataReady && minTimePassed }
    }

    /// Actions handled by the welcome feature.
    enum Action {
        /// Starts the parallel data-fetch and minimum-time effects.
        case onAppear
        /// Fired when salon data has been successfully fetched from Firebase.
        case dataLoaded(IdentifiedArrayOf<Salon>)
        /// Fired when the Firebase fetch fails; the feature proceeds with an empty salon list.
        case dataFailed
        /// Fired when the minimum splash display duration has elapsed.
        case minTimeElapsed
        case delegate(Delegate)

        /// Delegate actions surfaced to the parent ``AppFeature``.
        @CasePathable
        enum Delegate: Equatable {
            /// Both readiness conditions are met; carry the user and preloaded salons into `MainFeature`.
            case readyToEnter(AppUser, IdentifiedArrayOf<Salon>)
        }
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.continuousClock) var clock

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let firebase = firebase
                return .merge(
                    .run { send in
                        do {
                            let salons = try await firebase.fetchAllSalons()
                            await send(.dataLoaded(IdentifiedArray(uniqueElements: salons)))
                        } catch {
                            await send(.dataFailed)
                        }
                    },
                    .run { [clock] send in
                        try? await clock.sleep(for: .seconds(1))
                        await send(.minTimeElapsed)
                    }
                )

            case .dataLoaded(let salons):
                state.salons = salons
                state.isDataReady = true
                if state.canProceed { return .send(.delegate(.readyToEnter(state.user, state.salons))) }
                return .none

            case .dataFailed:
                state.isDataReady = true
                if state.canProceed { return .send(.delegate(.readyToEnter(state.user, state.salons))) }
                return .none

            case .minTimeElapsed:
                state.minTimePassed = true
                if state.canProceed { return .send(.delegate(.readyToEnter(state.user, state.salons))) }
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
