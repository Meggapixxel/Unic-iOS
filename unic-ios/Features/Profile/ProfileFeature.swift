// FILE: unic-ios/Features/Profile/ProfileFeature.swift

import ComposableArchitecture
import Foundation

@Reducer
struct ProfileFeature {

    // MARK: - Path

    @Reducer
    struct Path {
        @ObservableState
        enum State: Equatable {
            case userActivity(UserActivityFeature.State)
            case sales(SalesFeature.State)
            case users(UsersFeature.State)
            case plans(PlansFeature.State)
        }

        enum Action {
            case userActivity(UserActivityFeature.Action)
            case sales(SalesFeature.Action)
            case users(UsersFeature.Action)
            case plans(PlansFeature.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: \.userActivity, action: \.userActivity) { UserActivityFeature() }
            Scope(state: \.sales, action: \.sales) { SalesFeature() }
            Scope(state: \.users, action: \.users) { UsersFeature() }
            Scope(state: \.plans, action: \.plans) { PlansFeature() }
        }
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var currentUser: AppUser
        var path: StackState<Path.State> = StackState()
        var showLogoutConfirm: Bool = false

        // Permissions (resolved at onLoad)
        var canViewSales: Bool = false
        var canViewUsers: Bool = false
        var canManagePlans: Bool = false

        init(currentUser: AppUser) {
            self.currentUser = currentUser
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case logoutTapped
        case logoutConfirmed
        case navigateToActivity
        case navigateToSales
        case navigateToUsers
        case navigateToPlans
        case path(StackActionOf<Path>)
    }

    // MARK: - Dependencies

    @Dependency(\.authClient) var auth

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {

            case .onLoad:
                state.canViewSales = auth.canViewSales()
                state.canViewUsers = auth.canViewUsers()
                state.canManagePlans = auth.canManagePlans()
                return .none

            case .logoutTapped:
                state.showLogoutConfirm = true
                return .none

            case .logoutConfirmed:
                state.showLogoutConfirm = false
                auth.logout()
                return .none

            case .navigateToActivity:
                state.path.append(.userActivity(UserActivityFeature.State(user: state.currentUser)))
                return .none

            case .navigateToSales:
                guard state.canViewSales else { return .none }
                state.path.append(.sales(SalesFeature.State()))
                return .none

            case .navigateToUsers:
                guard state.canViewUsers else { return .none }
                state.path.append(.users(UsersFeature.State()))
                return .none

            case .navigateToPlans:
                guard state.canManagePlans else { return .none }
                state.path.append(.plans(PlansFeature.State()))
                return .none

            case .path:
                return .none

            case .binding:
                return .none
            }
        }
        .forEach(\.path, action: \.path) { Path() }
    }
}

