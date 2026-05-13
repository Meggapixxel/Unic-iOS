import ComposableArchitecture
import Foundation

@Reducer
struct UsersFeature {
    @ObservableState
    struct State: Equatable {
        var users: [AppUser] = []
        var isLoading = false
        var error: String?
        var path = StackState<Path.State>()
    }

    @Reducer
    struct Path {
        @ObservableState
        enum State: Equatable {
            case userActivity(UserActivityFeature.State)
        }
        enum Action {
            case userActivity(UserActivityFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: \.userActivity, action: \.userActivity) { UserActivityFeature() }
        }
    }

    enum Action {
        case onLoad
        case loaded([AppUser])
        case failed(String)
        case userTapped(AppUser)
        case path(StackActionOf<Path>)
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onLoad:
                state.isLoading = true
                return .run { send in
                    do {
                        let users = try await firebase.fetchAllUsers()
                        await send(.loaded(users))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            case .loaded(let users):
                state.isLoading = false
                state.users = auth.isAdmin()
                    ? users
                    : users.filter { $0.role == auth.currentUser()?.role }
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
        .forEach(\.path, action: \.path) { Path() }
    }
}
