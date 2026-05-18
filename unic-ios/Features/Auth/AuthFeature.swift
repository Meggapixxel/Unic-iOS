import ComposableArchitecture
import Foundation

/// TCA reducer handling email/password authentication via Firebase.
@Reducer
struct AuthFeature {
    /// Form state for the login screen.
    @ObservableState
    struct State: Equatable {
        var email = ""
        var password = ""
        /// Whether a login network request is in-flight.
        var isLoading = false
        /// Human-readable error message shown below the form when login fails.
        var errorMessage: String?
    }

    /// Actions available on the authentication screen.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// User tapped the login button; triggers credential validation and network call.
        case loginTapped
        /// Login succeeded; auth-state observation in ``AppFeature`` will handle the transition.
        case loginSucceeded
        /// Login failed with the given error description.
        case loginFailed(String)
    }

    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
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
                let auth = auth
                return .run { [auth] send in
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
