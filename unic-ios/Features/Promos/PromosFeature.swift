import ComposableArchitecture
import Foundation

@Reducer
struct PromosFeature {

    // MARK: - Destination

    @Reducer
    enum Destination {
        case form(PromoFormFeature)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var promos: [PromoOffer] = []
        var error: String?
        var canManagePromos = false
        var selectedPromo: PromoOffer?
        var promoToDelete: PromoOffer?
        @Presents var destination: Destination.State?

        var displayed: [PromoOffer] { promos.filter { !$0.isPast } }
    }

    // MARK: - Action

    enum Action {
        case onLoad
        case promosLoaded([PromoOffer])
        case openAdd
        case openEdit(PromoOffer)
        case openDetail(PromoOffer)
        case closeDetail
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

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.canManagePromos = auth.canManagePromos()
                return .run { send in
                    do {
                        let promos = try await firebase.fetchPromos()
                        await send(.promosLoaded(promos))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .promosLoaded(let promos):
                state.promos = promos
                return .none

            case .openAdd:
                state.destination = .form(PromoFormFeature.State())
                return .none

            case .openEdit(let promo):
                state.destination = .form(PromoFormFeature.State(existing: promo))
                return .none

            case .openDetail(let promo):
                state.selectedPromo = promo
                return .none

            case .closeDetail:
                state.selectedPromo = nil
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
                return .run { send in
                    do {
                        try await firebase.deletePromo(id)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .cancelDelete:
                state.promoToDelete = nil
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
        .ifLet(\.$destination, action: \.destination)
    }
}
