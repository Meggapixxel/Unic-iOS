import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {

    @ObservableState
    enum State: Equatable {
        case loading
        case auth(AuthFeature.State)
        case welcome(WelcomeFeature.State)
        case main(MainFeature.State)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case let (.auth(l), .auth(r)): return l == r
            case let (.welcome(l), .welcome(r)): return l == r
            case let (.main(l), .main(r)): return l == r
            default: return false
            }
        }
    }

    enum Action {
        case onAppear
        case authStateChanged(AppUser?)
        case auth(AuthFeature.Action)
        case welcome(WelcomeFeature.Action)
        case main(MainFeature.Action)
    }

    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let authClient = auth
                return .run { send in
                    let stream = await MainActor.run { authClient.observeAuthState() }
                    for await user in stream {
                        await send(.authStateChanged(user))
                    }
                }

            case .authStateChanged(let user):
                if let user {
                    guard case .main = state else {
                        state = .welcome(WelcomeFeature.State(user: user))
                        return .none
                    }
                } else {
                    guard case .auth = state else {
                        state = .auth(AuthFeature.State())
                        return .none
                    }
                }
                return .none

            case .welcome(.delegate(.readyToEnter(let user, let salons))):
                state = .main(MainFeature.State(currentUser: user, preloadedSalons: salons))
                return .none

            case .auth, .welcome, .main:
                return .none
            }
        }
        .ifCaseLet(\.auth, action: \.auth) { AuthFeature() }
        .ifCaseLet(\.welcome, action: \.welcome) { WelcomeFeature() }
        .ifCaseLet(\.main, action: \.main) { MainFeature() }
    }
}
