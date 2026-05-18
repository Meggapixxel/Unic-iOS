import ComposableArchitecture
import Foundation

/// Root TCA reducer for the authenticated main-app experience, composing the four primary tab reducers
/// (Salons, Promos, Stock, Profile) and the floating `PlanBannerFeature` overlay.
///
/// **Entry point**
/// Created by `AppFeature` via `.welcome(.delegate(.readyToEnter(user, salons)))`. Optionally seeds
/// `salons.salons` with data preloaded during the welcome phase to avoid a duplicate Firebase fetch.
/// `MainView` dispatches `.onAppear`, which currently produces no effect (reserved for future use).
///
/// **Key action flows**
/// - `.binding` — Handled by `BindingReducer`; primarily drives `selectedTab` changes when the user taps
///   a bottom-tab button.
/// - `.salons / .promos / .stock / .profile / .planBanner` — Forwarded transparently to their respective
///   child reducers via `Scope`. `MainFeature` itself does not intercept these actions.
/// - `.onAppear` — No-op at this level; each child feature owns its own load lifecycle.
///
/// **Navigation**
/// Tab selection is bound through `$selectedTab` (four `Tab` cases: `.salons`, `.promos`, `.stock`,
/// `.profile`). Deep navigation within each tab is managed entirely by the child feature's own
/// `Path` / `Destination` state.
///
/// **Side effects**
/// None at this level. All async work (Firebase fetches, FlexiBee sync, auth refresh) is delegated
/// to child reducers (`SalonsFeature`, `PromosFeature`, `StockFeature`, `ProfileFeature`,
/// `PlanBannerFeature`).
@Reducer
struct MainFeature {
    /// State shared across all tabs of the main interface.
    @ObservableState
    struct State: Equatable {
        /// The currently selected bottom tab.
        var selectedTab: Tab = .salons
        /// The authenticated user; updated in-place when Firebase auth emits a refresh.
        var currentUser: AppUser
        var salons = SalonsFeature.State()
        var promos = PromosFeature.State()
        var stock = StockFeature.State()
        var profile: ProfileFeature.State
        var planBanner = PlanBannerFeature.State()

        /// Available bottom-tab destinations.
        enum Tab: String, Equatable, Hashable, CaseIterable { case salons, promos, stock, profile }

        /// Initialises state, optionally seeding the salons list with data preloaded during the welcome screen.
        /// - Parameters:
        ///   - currentUser: The signed-in user.
        ///   - preloadedSalons: Salons fetched before the main screen appeared; skips an extra round-trip when non-empty.
        init(currentUser: AppUser, preloadedSalons: IdentifiedArrayOf<Salon> = []) {
            self.currentUser = currentUser
            self.profile = ProfileFeature.State(currentUser: currentUser)
            if !preloadedSalons.isEmpty {
                self.salons.salons = preloadedSalons
            }
        }
    }

    /// Actions available at the main-feature level.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case salons(SalonsFeature.Action)
        case promos(PromosFeature.Action)
        case stock(StockFeature.Action)
        case profile(ProfileFeature.Action)
        case planBanner(PlanBannerFeature.Action)
        case onAppear
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Scope(state: \.salons, action: \.salons) { SalonsFeature() }
        Scope(state: \.promos, action: \.promos) { PromosFeature() }
        Scope(state: \.stock, action: \.stock) { StockFeature() }
        Scope(state: \.profile, action: \.profile) { ProfileFeature() }
        Scope(state: \.planBanner, action: \.planBanner) { PlanBannerFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            case .binding, .salons, .promos, .stock, .profile, .planBanner:
                return .none
            }
        }
    }
}
