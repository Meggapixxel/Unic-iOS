import ComposableArchitecture
import Foundation

/// TCA reducer for the post-login splash/loading screen that preloads salon data before entering the main interface.
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
