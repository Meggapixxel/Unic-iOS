import ComposableArchitecture
import Foundation

@Reducer
struct PromoDetailFeature {
    @ObservableState
    struct State: Equatable {
        var promo: PromoOffer
        var canManagePromos: Bool
        var language: AppLanguage
        var isTogglingEnabled = false
        var isPickingActivationDates = false
        var activateFrom: Date
        var activateTo: Date

        init(promo: PromoOffer, canManagePromos: Bool, language: AppLanguage) {
            @Dependency(\.date) var date
            let now = date()
            self.promo = promo
            self.canManagePromos = canManagePromos
            self.language = language
            self.activateFrom = promo.validFrom ?? now
            self.activateTo = promo.validTo ?? Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case closeTapped
        case editTapped
        case toggleEnabled
        case activateDateConfirmed
        case activatePickerDismissed
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
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .closeTapped:
                return .run { [dismiss] _ in await dismiss() }
            case .editTapped:
                return .send(.delegate(.editRequested))

            case .toggleEnabled:
                if state.promo.isEnabled {
                    guard let id = state.promo.id else { return .none }
                    state.isTogglingEnabled = true
                    let firebase = firebase
                    return .run { [firebase] send in
                        do {
                            let saved = try await firebase.deactivatePromo(id)
                            await send(.toggleSucceeded(saved))
                        } catch {
                            await send(.toggleFailed)
                        }
                    }
                } else {
                    state.isPickingActivationDates = true
                    return .none
                }

            case .activateDateConfirmed:
                guard let id = state.promo.id else {
                    state.isPickingActivationDates = false
                    return .none
                }
                state.isPickingActivationDates = false
                state.isTogglingEnabled = true
                let firebase = firebase
                let vf = state.activateFrom
                let vt = state.activateTo
                return .run { [firebase] send in
                    do {
                        let saved = try await firebase.activatePromo(id, vf, vt)
                        await send(.toggleSucceeded(saved))
                    } catch {
                        await send(.toggleFailed)
                    }
                }

            case .activatePickerDismissed:
                state.isPickingActivationDates = false
                return .none

            case .toggleSucceeded(let promo):
                state.isTogglingEnabled = false
                state.promo = promo
                return .send(.delegate(.didToggle(promo)))

            case .toggleFailed:
                state.isTogglingEnabled = false
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
