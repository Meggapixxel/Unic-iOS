import ComposableArchitecture
import Foundation

/// Displays the full detail of a single `PromoOffer` and, for admin users, allows toggling
/// it between enabled and disabled states with date-range selection when enabling.
///
/// **Entry point**
/// Presented as a modal sheet by `PromosFeature` via `.openDetail(promo)`, or opened directly
/// with `isPickingActivationDates = true` when the parent calls `.toggleEnabled` on a disabled
/// promo. No separate load action — the promo is passed in via the `State` initialiser.
///
/// **Key action flows**
/// - `.closeTapped` — calls `@Dependency(\.dismiss)` to close the sheet.
/// - `.editTapped` — sends `.delegate(.editRequested)` so `PromosFeature` can swap the
///   destination from detail to the edit form without dismissing.
/// - `.toggleEnabled` — if currently enabled, immediately calls `firebase.deactivatePromo(id)`;
///   if currently disabled, sets `isPickingActivationDates = true` to show the date picker.
/// - `.activateDateConfirmed` — hides the picker, sets `isTogglingEnabled = true`, then calls
///   `firebase.activatePromo(id, activateFrom, activateTo)`.
/// - `.activatePickerDismissed` — user cancelled the date picker; resets `isPickingActivationDates`.
/// - `.toggleSucceeded(promo)` — updates `state.promo` with the server response and sends
///   `.delegate(.didToggle(promo))` so `PromosFeature` can patch its list.
/// - `.toggleFailed` — clears the `isTogglingEnabled` spinner without surfacing an alert
///   (error handling is handled by the parent or left silent).
///
/// **Navigation**
/// No `Path` or nested `Destination`. The activation-date picker is an inline sheet controlled
/// by the `isPickingActivationDates` bool state.
///
/// **Side effects**
/// - `firebase.deactivatePromo(id)` — Firebase write to mark the promo inactive.
/// - `firebase.activatePromo(id, validFrom, validTo)` — Firebase write to re-enable the promo
///   with the user-chosen date range.
/// Both calls run inside `Effect.run` and report results via `.toggleSucceeded` / `.toggleFailed`.
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
