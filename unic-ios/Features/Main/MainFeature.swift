import ComposableArchitecture
import Foundation

@Reducer
struct MainFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .salons
        var currentUser: AppUser
        var salons = SalonsFeature.State()
        var promos = PromosFeature.State()
        var stock = StockFeature.State()
        var profile: ProfileFeature.State
        var planBanner = PlanBannerFeature.State()
        var showGreeting = false

        enum Tab: Equatable { case salons, promos, stock, profile }

        init(currentUser: AppUser) {
            self.currentUser = currentUser
            self.profile = ProfileFeature.State(currentUser: currentUser)
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case salons(SalonsFeature.Action)
        case promos(PromosFeature.Action)
        case stock(StockFeature.Action)
        case profile(ProfileFeature.Action)
        case planBanner(PlanBannerFeature.Action)
        case onAppear
        case greetingTimerFired
    }

    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        BindingReducer()
        Scope(state: \.salons, action: \.salons) { SalonsFeature() }
        Scope(state: \.promos, action: \.promos) { PromosFeature() }
        Scope(state: \.stock, action: \.stock) { StockFeature() }
        Scope(state: \.profile, action: \.profile) { ProfileFeature() }
        Scope(state: \.planBanner, action: \.planBanner) { PlanBannerFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.showGreeting = true
                return .run { send in
                    try await clock.sleep(for: .seconds(2.5))
                    await send(.greetingTimerFired)
                }
            case .greetingTimerFired:
                state.showGreeting = false
                return .none
            case .binding, .salons, .promos, .stock, .profile, .planBanner:
                return .none
            }
        }
    }
}
