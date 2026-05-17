import ComposableArchitecture
import Foundation

@Reducer
struct PromoFormFeature {
    @ObservableState
    struct State: Equatable {
        var titleEn: String = ""
        var titleUk: String = ""
        var titleRu: String = ""
        var descriptionEn: String = ""
        var descriptionUk: String = ""
        var descriptionRu: String = ""
        var category: String = "Other"
        var isSaving = false
        var alertMessage: String?
        var existing: PromoOffer?

        var isValid: Bool { !titleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        init(existing: PromoOffer? = nil) {
            self.existing = existing
            self.titleEn       = existing?.content[AppLanguage.en.rawValue]?.title ?? ""
            self.titleUk       = existing?.content[AppLanguage.ua.rawValue]?.title ?? ""
            self.titleRu       = existing?.content[AppLanguage.ru.rawValue]?.title ?? ""
            self.descriptionEn = existing?.content[AppLanguage.en.rawValue]?.description ?? ""
            self.descriptionUk = existing?.content[AppLanguage.ua.rawValue]?.description ?? ""
            self.descriptionRu = existing?.content[AppLanguage.ru.rawValue]?.description ?? ""
            self.category      = existing?.category ?? "Other"
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case closeTapped
        case saveTapped
        case saveSucceeded(PromoOffer)
        case saveFailed(String)
        case dismissAlert
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .closeTapped:
                return .run { [dismiss] _ in await dismiss() }
            case .saveTapped:
                guard state.isValid else { return .none }
                state.isSaving = true
                var promoContent: [String: PromoContent] = [:]
                let langs = [(AppLanguage.en.rawValue, state.titleEn, state.descriptionEn),
                             (AppLanguage.ua.rawValue, state.titleUk, state.descriptionUk),
                             (AppLanguage.ru.rawValue, state.titleRu, state.descriptionRu)]
                for (lang, t, d) in langs {
                    let title = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        promoContent[lang] = PromoContent(
                            title: title,
                            description: d.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
                let promo = PromoOffer(
                    id: state.existing?.id,
                    validFrom: state.existing?.validFrom,
                    validTo: state.existing?.validTo,
                    createdBy: auth.currentUser()?.id ?? "",
                    category: state.category,
                    content: promoContent
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
