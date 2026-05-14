import ComposableArchitecture
import Foundation

@Reducer
struct WelcomeFeature {
    @ObservableState
    struct State: Equatable {
        let user: AppUser
        var salons: IdentifiedArrayOf<Salon> = []
        var isDataReady = false
        var isLocationChecked = false
        var minTimePassed = false

        var canProceed: Bool { isDataReady && isLocationChecked && minTimePassed }
    }

    enum Action {
        case onAppear
        case dataLoaded(IdentifiedArrayOf<Salon>)
        case dataFailed
        case locationChecked
        case minTimeElapsed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
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

            case .locationChecked:
                state.isLocationChecked = true
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
