import ComposableArchitecture
import Foundation

/// TCA feature for viewing and toggling a single promo offer, with activation-date picking.
@Reducer
struct PromoDetailFeature {
    /// Observable state for the promo detail sheet.
    @ObservableState
    struct State: Equatable {
        /// The promo offer being displayed; updated in-place after a toggle.
        var promo: PromoOffer
        /// Whether the current user has permission to enable/disable or edit promos.
        var canManagePromos: Bool
        /// The language used to render localised title and description.
        var language: AppLanguage
        /// `true` while a Firebase enable/disable call is in-flight.
        var isTogglingEnabled = false
        /// `true` when the activation-date picker sheet is being shown.
        var isPickingActivationDates = false
        /// Start date chosen in the activation picker.
        var activateFrom: Date
        /// End date chosen in the activation picker.
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
        /// Toggles the promo between enabled and disabled; shows date picker when enabling.
        case toggleEnabled
        /// Confirms the chosen activation dates and triggers the Firebase activate call.
        case activateDateConfirmed
        case activatePickerDismissed
        case toggleSucceeded(PromoOffer)
        case toggleFailed
        case delegate(Delegate)

        /// Actions forwarded to the parent feature.
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
