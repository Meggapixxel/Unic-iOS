import ComposableArchitecture
import Foundation

@Reducer
struct PromoFormFeature {
    @ObservableState
    struct State: Equatable {
        var title: String = ""
        var description: String = ""
        var validFrom: Date = Date()
        var validTo: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        var isSaving = false
        var alertMessage: String?
        var existing: PromoOffer?

        var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        init(existing: PromoOffer? = nil) {
            self.existing = existing
            self.title = existing?.title ?? ""
            self.description = existing?.description ?? ""
            self.validFrom = existing?.validFrom ?? Date()
            self.validTo = existing?.validTo ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveTapped
        case saveSucceeded(PromoOffer)
        case saveFailed(String)
        case dismissAlert
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .saveTapped:
                guard state.isValid else { return .none }
                state.isSaving = true
                let promo = PromoOffer(
                    id: state.existing?.id,
                    title: state.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: state.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    validFrom: state.validFrom,
                    validTo: state.validTo,
                    createdBy: auth.currentUser()?.id ?? ""
                )
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let saved = try await firebase.savePromo(promo)
                        await send(.saveSucceeded(saved))
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }
            case .saveSucceeded:
                state.isSaving = false
                return .none
            case .saveFailed(let msg):
                state.isSaving = false
                state.alertMessage = msg
                return .none
            case .dismissAlert:
                state.alertMessage = nil
                return .none
            }
        }
    }
}
