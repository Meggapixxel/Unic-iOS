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
        case planStatsLoaded(salons: Int, testDrives: Int)
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
                guard let plan = state.currentUser.activePlan else { return .none }
                let firebase = firebase
                let userId = state.currentUser.id
                let startDate = plan.startDate
                let endDate = plan.endDate
                return .run { send in
                    let entries = (try? await firebase.fetchUserActivity(userId)) ?? []
                    let inPlan = entries.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
                    await send(.planStatsLoaded(
                        salons: inPlan.count,
                        testDrives: inPlan.filter { $0.status == .testDrive }.count
                    ))
                }

            case let .planStatsLoaded(salons, testDrives):
                state.currentUser.activePlan?.salonsVisited = salons
                state.currentUser.activePlan?.testDriveCount = testDrives
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

