import ComposableArchitecture
import Foundation

@Reducer
struct AuthFeature {
    @ObservableState
    struct State: Equatable {
        var email = ""
        var password = ""
        var isLoading = false
        var errorMessage: String?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case loginTapped
        case loginSucceeded
        case loginFailed(String)
    }

    @Dependency(\.authClient) var auth

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .loginTapped:
                guard !state.email.isEmpty, !state.password.isEmpty else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                let email = state.email
                let password = state.password
                return .run { send in
                    do {
                        try await auth.login(email, password)
                        await send(.loginSucceeded)
                    } catch {
                        await send(.loginFailed(error.localizedDescription))
                    }
                }
            case .loginSucceeded:
                state.isLoading = false
                return .none
            case .loginFailed(let msg):
                state.isLoading = false
                state.errorMessage = msg
                return .none
            }
        }
    }
}
