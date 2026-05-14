import ComposableArchitecture
import Foundation

@Reducer
struct PromoDetailFeature {
    @ObservableState
    struct State: Equatable {
        var promo: PromoOffer
        var canManagePromos: Bool
        var isTogglingEnabled = false
    }

    enum Action {
        case closeTapped
        case editTapped
        case toggleEnabled
        case toggleSucceeded(PromoOffer)
        case toggleFailed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case editRequested
            case didToggle(PromoOffer)
        }
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .closeTapped:
                return .run { [dismiss] _ in await dismiss() }
            case .editTapped:
                return .send(.delegate(.editRequested))
            case .toggleEnabled:
                state.promo.isEnabled.toggle()
                state.isTogglingEnabled = true
                let updated = state.promo
                let firebase = firebase
                return .run { send in
                    do {
                        let saved = try await firebase.savePromo(updated)
                        await send(.toggleSucceeded(saved))
                    } catch {
                        await send(.toggleFailed)
                    }
                }
            case .toggleSucceeded(let promo):
                state.isTogglingEnabled = false
                state.promo = promo
                return .send(.delegate(.didToggle(promo)))
            case .toggleFailed:
                state.isTogglingEnabled = false
                state.promo.isEnabled.toggle()
                return .none
            case .delegate:
                return .none
            }
        }
    }
}
