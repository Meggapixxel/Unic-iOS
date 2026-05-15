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
        case allTopProducts(AllTopProductsFeature)
        case users(UsersFeature)
        case plans(PlansFeature)
        case productDetail(ProductDetailFeature)
        case clientDetail(ClientDetailFeature)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var currentUser: AppUser
        var activityEntries: [UserActivityEntry] = []
        var planHistory: [UserPlanHistoryEntry] = []
        var path: StackState<Path.State> = StackState()
        var showLogoutConfirm: Bool = false

        // Permissions (resolved at onLoad)
        var canViewSales: Bool = false
        var canViewUsers: Bool = false
        var canManagePlans: Bool = false

        init(currentUser: AppUser) {
            self.currentUser = currentUser
        }

        var salonsInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate }.count
        }

        var testDrivesInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate && $0.status == .testDrive }.count
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case activityLoaded([UserActivityEntry])
        case planHistoryLoaded([UserPlanHistoryEntry])
        case logoutTapped
        case logoutConfirmed
        case navigateToActivity
        case navigateToSales
        case navigateToUsers
        case navigateToClients
        case navigateToPlans
        case path(StackActionOf<Path>)
    }

    // MARK: - Dependencies

    @Dependency(\.authClient) var auth
    @Dependency(\.firebaseClient) var firebase
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
                let firebase = firebase
                let auth = auth
                let userId = state.currentUser.id
                return .run { send in
                    let refreshed = await auth.refreshCurrentUser()
                    let hasPlan = refreshed?.activePlan != nil
                    if hasPlan {
                        let entries = (try? await firebase.fetchUserActivity(userId)) ?? []
                        await send(.activityLoaded(entries))
                    }
                    let history = (try? await firebase.fetchPlanHistory(userId)) ?? []
                    await send(.planHistoryLoaded(history))
                }

            case let .activityLoaded(entries):
                state.activityEntries = entries
                return .none

            case let .planHistoryLoaded(history):
                state.planHistory = history
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

            case .navigateToClients:
                guard state.canViewSales else { return .none }
                let allInvoices = flexiBeeClient.invoices()
                let clients = Dictionary(grouping: allInvoices) { $0.clientName }
                    .map { (name: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
                    .sorted { $0.revenue > $1.revenue }
                state.path.append(.allTopClients(AllTopClientsFeature.State(clients: clients)))
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

            case .path(.element(_, .sales(.clientTapped(let name)))):
                let allInvoices = flexiBeeClient.invoices()
                let clientInvoices = allInvoices.filter { $0.clientName == name }
                let code = clientInvoices.first?.clientCode
                state.path.append(.clientDetail(ClientDetailFeature.State(
                    clientName: name, clientCode: code,
                    canEdit: auth.canEditInvoice(),
                    canEditClient: auth.canEditClient(),
                    invoices: clientInvoices
                )))
                return .none

            case .path(.element(let id, .sales(.seeAllTopProductsTapped))):
                if case let .sales(salesState) = state.path[id: id] {
                    state.path.append(.allTopProducts(AllTopProductsFeature.State(products: salesState.topProducts)))
                }
                return .none

            case .path(.element(_, .invoiceDetail(.deleteCompleted))):
                state.path.removeLast()
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                }

            case .path(.element(_, .invoiceDetail(.productTapped(let code)))):
                let stock = flexiBeeClient.stockWithPrices()
                if let product = stock.first(where: { $0.code == code }) {
                    state.path.append(.productDetail(ProductDetailFeature.State(product: product)))
                }
                return .none

            case .path(.element(let id, .invoiceDetail(.clientTapped))):
                if case let .invoiceDetail(detailState) = state.path[id: id] {
                    let name = detailState.invoice.clientName
                    let code = detailState.invoice.clientCode
                    let allInvoices = flexiBeeClient.invoices()
                    let clientInvoices = allInvoices.filter {
                        code != nil ? $0.clientCode == code : $0.clientName == name
                    }
                    state.path.append(.clientDetail(ClientDetailFeature.State(
                        clientName: name, clientCode: code,
                        canEdit: auth.canEditInvoice(),
                        canEditClient: auth.canEditClient(),
                        invoices: clientInvoices
                    )))
                }
                return .none

            case .path(.element(_, .allTopProducts(.productTapped(let code)))):
                let stock = flexiBeeClient.stockWithPrices()
                if let product = stock.first(where: { $0.code == code }) {
                    state.path.append(.productDetail(ProductDetailFeature.State(product: product)))
                }
                return .none

            case .path(.element(_, .allTopClients(.clientTapped(let name)))):
                let allInvoices = flexiBeeClient.invoices()
                let clientInvoices = allInvoices.filter { $0.clientName == name }
                let code = clientInvoices.first?.clientCode
                state.path.append(.clientDetail(ClientDetailFeature.State(
                    clientName: name, clientCode: code,
                    canEdit: auth.canEditInvoice(),
                    canEditClient: auth.canEditClient(),
                    invoices: clientInvoices
                )))
                return .none

            case .path(.element(_, .clientDetail(.invoiceTapped(let invoice)))):
                state.path.append(.invoiceDetail(InvoiceDetailFeature.State(invoice: invoice)))
                return .none

            case .path(.element(_, .userActivity(.navigateToPlans))):
                state.path.append(.plans(PlansFeature.State()))
                return .none

            case .path(.element(_, .users(.userTapped(let user)))):
                state.path.append(.userActivity(UserActivityFeature.State(user: user)))
                return .none

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

