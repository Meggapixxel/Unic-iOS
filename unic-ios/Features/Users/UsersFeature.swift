import ComposableArchitecture
import Foundation

/// TCA feature for the users list, loading app users and navigating to their activity screens.
@Reducer
struct UsersFeature {
    /// Observable state for the users list screen.
    @ObservableState
    struct State: Equatable {
        /// Users visible to the current role (all users for admins; same-role only for others).
        var users: [AppUser] = []
        var isLoading = false
        var error: String?
        var path = StackState<Path.State>()
    }

    /// Navigation stack destinations reachable from the users list.
    @Reducer
    enum Path {
        case userActivity(UserActivityFeature)
    }

    enum Action {
        case onLoad
        case loaded([AppUser])
        case failed(String)
        /// Pushes the activity screen for the tapped user onto the navigation stack.
        case userTapped(AppUser)
        case path(StackActionOf<Path>)
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onLoad:
                state.isLoading = true
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let users = try await firebase.fetchAllUsers()
                        await send(.loaded(users))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            case .loaded(let users):
                state.isLoading = false
                let isAdmin = auth.isAdmin()
                let role = auth.currentUser()?.role
                state.users = isAdmin
                    ? users
                    : users.filter { $0.role == role }
                return .none
            case .failed(let msg):
                state.isLoading = false
                state.error = msg
                return .none
            case .userTapped(let user):
                state.path.append(.userActivity(UserActivityFeature.State(user: user)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension UsersFeature.Path.State: Equatable {}
