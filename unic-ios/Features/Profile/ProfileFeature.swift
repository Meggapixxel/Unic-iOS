// FILE: unic-ios/Features/Profile/ProfileFeature.swift

import ComposableArchitecture
import Foundation

@Reducer
struct ProfileFeature {

    // MARK: - Path

    @Reducer
    enum Path {
        case userActivity(UserActivityFeature)
        case sales(SalesFeature)
        case invoiceDetail(InvoiceDetailFeature)
        case allTopClients(AllTopClientsFeature)
        case users(UsersFeature)
        case plans(PlansFeature)
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
    @Dependency(\.flexiBeeClient) var flexiBeeClient

    // MARK: - Body

    var body: some Reducer<State, Action> {
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

            // MARK: Sales sub-navigation (flat stack)

            case .path(.element(_, .sales(.invoiceTapped(let invoice)))):
                state.path.append(.invoiceDetail(InvoiceDetailFeature.State(invoice: invoice)))
                return .none

            case .path(.element(let id, .sales(.seeAllTopClientsTapped))):
                if case let .sales(salesState) = state.path[id: id] {
                    state.path.append(.allTopClients(AllTopClientsFeature.State(clients: salesState.topClients)))
                }
                return .none

            case .path(.element(_, .invoiceDetail(.deleteCompleted))):
                state.path.removeLast()
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                }

            case .path:
                return .none

            case .binding:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension ProfileFeature.Path.State: Equatable {}

