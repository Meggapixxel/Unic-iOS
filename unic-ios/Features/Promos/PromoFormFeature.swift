import ComposableArchitecture
import Foundation

/// Handles the create/edit form for a `PromoOffer`, collecting per-language title and
/// description fields plus a category picker, then saving the result to Firebase.
///
/// **Entry point**
/// Presented as a modal sheet by `PromosFeature` via `.openAdd` (blank form) or `.openEdit(promo)`
/// (pre-filled). The `State` initialiser populates fields from `existing` when provided.
/// No `.onLoad` action — all state is ready at init time.
///
/// **Key action flows**
/// - `.binding` — two-way binds all text fields and `category` via `BindingReducer`.
/// - `.closeTapped` — calls `@Dependency(\.dismiss)` to close the sheet without saving.
/// - `.saveTapped` — guards `isValid` (English title non-empty), builds a `PromoContent`
///   dictionary keyed by `AppLanguage.rawValue` (skipping blank locale entries), constructs
///   a `PromoOffer` model (reusing the existing ID and dates if editing), sets `isSaving = true`,
///   and calls `firebase.savePromo(promo)`.
/// - `.saveSucceeded(promo)` — clears `isSaving`; the parent `PromosFeature` intercepts this
///   action via `.destination(.presented(.form(.saveSucceeded)))` to dismiss the sheet and
///   update the promo list.
/// - `.saveFailed(msg)` — clears `isSaving` and sets `alertMessage` for an error alert.
/// - `.dismissAlert` — clears `alertMessage`.
///
/// **Navigation**
/// No `Path` or `Destination`; the form is itself a modal sheet with no child navigation.
///
/// **Side effects**
/// - `firebase.savePromo(_:)` — async Firebase write that either creates a new promo document
///   or updates the existing one (determined by whether `PromoOffer.id` is nil); runs inside
///   `Effect.run` and reports results via `.saveSucceeded` / `.saveFailed`.
@Reducer
struct PromoFormFeature {
    /// Observable state for the promo create/edit form.
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
        /// Non-nil when editing an existing offer; `nil` for creation.
        var existing: PromoOffer?

        /// `true` when the English title contains at least one non-whitespace character.
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
