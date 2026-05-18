import ComposableArchitecture
import Foundation

/// TCA feature managing the promos list, category filtering, language selection, and enable/disable toggling.
@Reducer
struct PromosFeature {

    // MARK: - Destination

    /// Modal destinations shown from the promos list.
    @Reducer
    struct Destination {
        @ObservableState
        enum State: Equatable {
            case detail(PromoDetailFeature.State)
            case form(PromoFormFeature.State)
        }
        enum Action {
            case detail(PromoDetailFeature.Action)
            case form(PromoFormFeature.Action)
        }
        var body: some Reducer<State, Action> {
            Reduce { _, _ in .none }
                .ifCaseLet(\.detail, action: \.detail) { PromoDetailFeature() }
                .ifCaseLet(\.form, action: \.form) { PromoFormFeature() }
        }
    }

    // MARK: - State

    /// Observable state for the promos tab.
    @ObservableState
    struct State: Equatable {
        /// All promos loaded from Firebase.
        var promos: [PromoOffer] = []
        /// Ordered list of available category strings fetched from Firebase.
        var categories: [String] = []
        var error: String?
        var canManagePromos = false
        /// When `true` (admin only), shows inactive/disabled promos instead of active ones.
        var showAll = false
        /// Currently selected display language for promo titles and descriptions.
        var language: AppLanguage = Locale.current.appLanguage
        /// Active category chips; empty means all categories.
        var selectedCategories: Set<String> = []
        /// The promo pending deletion confirmation; `nil` when no confirmation is shown.
        var promoToDelete: PromoOffer?
        @Presents var destination: Destination.State?

        /// Category strings that are represented in the current base set of displayed promos.
        var availableCategories: [String] {
            let base = canManagePromos
                ? (showAll ? promos.filter { !$0.isActive || !$0.isEnabled } : promos.filter { $0.isActive && $0.isEnabled })
                : promos.filter { $0.isActive && $0.isEnabled }
            let presentInBase = Set(base.map { $0.category })
            return categories.filter { presentInBase.contains($0) }
        }

        /// Promos filtered by the active/inactive toggle and selected category chips.
        var displayed: [PromoOffer] {
            let base: [PromoOffer]
            if canManagePromos {
                base = showAll
                    ? promos.filter { !$0.isActive || !$0.isEnabled }
                    : promos.filter { $0.isActive && $0.isEnabled }
            } else {
                base = promos.filter { $0.isActive && $0.isEnabled }
            }
            guard !selectedCategories.isEmpty else { return base }
            return base.filter { selectedCategories.contains($0.category) }
        }
    }

    // MARK: - Action

    enum Action {
        case onLoad
        case promosLoaded([PromoOffer])
        case categoriesLoaded([String])
        case openAdd
        case openEdit(PromoOffer)
        case openDetail(PromoOffer)
        case toggleEnabled(PromoOffer)
        case promoDeactivated(PromoOffer)
        case toggleShowDisabled
        case setLanguage(AppLanguage)
        case toggleCategory(String)
        case deleteTapped(PromoOffer)
        case deleteConfirmed
        case cancelDelete
        case failed(String)
        case destination(PresentationAction<Destination.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.canManagePromos = auth.canManagePromos()
                let firebase = firebase
                return .run { [firebase] send in
                    async let promos = firebase.fetchPromos()
                    async let categories = firebase.fetchPromoCategories()
                    do {
                        await send(.promosLoaded(try promos))
                        await send(.categoriesLoaded(try categories))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .promosLoaded(let promos):
                state.promos = promos
                return .none

            case .categoriesLoaded(let cats):
                state.categories = cats
                return .none

            case .openAdd:
                state.destination = .form(PromoFormFeature.State())
                return .none

            case .openEdit(let promo):
                state.destination = .form(PromoFormFeature.State(existing: promo))
                return .none

            case .openDetail(let promo):
                state.destination = .detail(PromoDetailFeature.State(
                    promo: promo,
                    canManagePromos: state.canManagePromos,
                    language: state.language
                ))

                return .none

            case .toggleShowDisabled:
                state.showAll.toggle()
                return .none

            case .toggleCategory(let cat):
                if state.selectedCategories.contains(cat) {
                    state.selectedCategories.remove(cat)
                } else {
                    state.selectedCategories.insert(cat)
                }
                return .none

            case .setLanguage(let lang):
                state.language = lang
                if case .detail(var detailState) = state.destination {
                    detailState.language = lang
                    state.destination = .detail(detailState)
                }
                return .none

            case .toggleEnabled(let promo):
                if promo.isEnabled {
                    guard let id = promo.id else { return .none }
                    let firebase = firebase
                    return .run { [firebase] send in
                        do {
                            let saved = try await firebase.deactivatePromo(id)
                            await send(.promoDeactivated(saved))
                        } catch {
                            await send(.failed(error.localizedDescription))
                        }
                    }
                } else {
                    var detailState = PromoDetailFeature.State(promo: promo, canManagePromos: state.canManagePromos, language: state.language)
                    detailState.isPickingActivationDates = true
                    state.destination = .detail(detailState)
                    return .none
                }

            case .promoDeactivated(let promo):
                if let idx = state.promos.firstIndex(where: { $0.id == promo.id }) {
                    state.promos[idx] = promo
                }
                return .none

            case .deleteTapped(let promo):
                state.promoToDelete = promo
                return .none

            case .deleteConfirmed:
                guard let promo = state.promoToDelete, let id = promo.id else {
                    state.promoToDelete = nil
                    return .none
                }
                state.promos.removeAll { $0.id == id }
                state.promoToDelete = nil
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        try await firebase.deletePromo(id)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .cancelDelete:
                state.promoToDelete = nil
                return .none

            case .destination(.presented(.detail(.delegate(.editRequested)))):
                guard case .detail(let detailState) = state.destination else { return .none }
                let promo = detailState.promo
                state.destination = .form(PromoFormFeature.State(existing: promo))
                return .none

            case .destination(.presented(.detail(.delegate(.didToggle(let promo))))):
                if let idx = state.promos.firstIndex(where: { $0.id == promo.id }) {
                    state.promos[idx] = promo
                }
                return .none

            case .destination(.presented(.form(.saveSucceeded(let promo)))):
                state.destination = nil
                if let idx = state.promos.firstIndex(where: { $0.id == promo.id }) {
                    state.promos[idx] = promo
                } else {
                    state.promos.insert(promo, at: 0)
                }
                return .none

            case .failed(let msg):
                state.error = msg
                return .none

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) { Destination() }
    }
}
