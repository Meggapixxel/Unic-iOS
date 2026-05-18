// FILE: unic-ios/Features/Profile/ProfileFeature.swift

import ComposableArchitecture
import Foundation

/// TCA reducer for the Profile tab, displaying the current user's in-plan KPIs, plan history, and providing
/// role-gated navigation to activity logs, sales, users, clients, and plan management.
///
/// **Entry point**
/// `ProfileView` dispatches `.onLoad` (not `.onAppear`) once the view is ready. `.onLoad` resolves
/// permission flags synchronously from `authClient`, then launches an async effect that refreshes the
/// current user from Firebase, conditionally fetches activity entries (only when an active plan exists),
/// and always fetches plan history.
///
/// **Key action flows**
/// - `.onLoad` — Resolves `canViewSales`, `canViewUsers`, `canManagePlans` from `authClient` synchronously.
///   Then runs a single `Effect.run` that:
///   1. Calls `auth.refreshCurrentUser()`.
///   2. If the refreshed user has an active plan, fetches `firebase.fetchUserActivity(userId)` → `.activityLoaded`.
///   3. Always fetches `firebase.fetchPlanHistory(userId)` → `.planHistoryLoaded`.
/// - `.logoutTapped` — Sets `showLogoutConfirm = true` to show a confirmation dialog.
/// - `.logoutConfirmed` — Calls `auth.logout()` synchronously; `AppFeature`'s auth stream drives the
///   transition back to `.auth`.
/// - `.navigateToActivity` — Pushes `UserActivityFeature` onto the navigation stack.
/// - `.navigateToSales` — Pushes `SalesFeature` (guarded by `canViewSales`).
/// - `.navigateToUsers` — Pushes `UsersFeature` (guarded by `canViewUsers`).
/// - `.navigateToClients` — Reads cached FlexiBee invoices synchronously, aggregates revenue by client,
///   and pushes `AllTopClientsFeature` (guarded by `canViewSales`).
/// - `.navigateToPlans` — Pushes `PlansFeature` (guarded by `canManagePlans`).
///
/// **Navigation (`Path`)**
/// Uses a `@Reducer enum Path` / `StackState<Path.State>` navigation stack with these destinations:
/// - `.userActivity` — User's chronological activity log; tapping "Plans" from here pushes `.plans`.
/// - `.sales` — Sales dashboard; supports sub-navigation to `.invoiceDetail`, `.allTopClients`,
///   `.allTopProducts`, and `.clientDetail` all pushed flat onto the same stack.
/// - `.invoiceDetail` — Single invoice view; handles `.deleteCompleted` (pops + forces FlexiBee sync),
///   `.productTapped` (pushes `.productDetail`), and `.clientTapped` (pushes `.clientDetail`).
/// - `.allTopClients` — Ranked client list; `.clientTapped` pushes `.clientDetail`.
/// - `.allTopProducts` — Ranked product list; `.productTapped` pushes `.productDetail`.
/// - `.clientDetail` — Client's full invoice history; `.invoiceTapped` pushes `.invoiceDetail`.
/// - `.users` — User list; `.userTapped` pushes `.userActivity` for the selected user.
/// - `.plans` — Plan management screen (also reachable from `userActivity`).
/// - `.productDetail` — Read-only product detail pushed from invoice or top-products screens.
///
/// **Side effects**
/// - `auth.refreshCurrentUser()` — Firebase user refresh on every `.onLoad`.
/// - `firebase.fetchUserActivity(_:)` — Fetches activity entries when an active plan is present.
/// - `firebase.fetchPlanHistory(_:)` — Fetches completed plan history unconditionally on load.
/// - `flexiBeeClient.invoices()` — Synchronous cache read when navigating to clients.
/// - `flexiBeeClient.stockWithPrices()` — Synchronous cache read when navigating to product detail.
/// - `flexiBeeClient.forceSync()` — Async re-sync triggered after an invoice is deleted.
/// - `auth.logout()` — Synchronous Firebase sign-out on confirmation.
@Reducer
struct ProfileFeature {

    // MARK: - Path

    /// All screens reachable via the profile navigation stack.
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

    /// State for the profile tab and its navigation stack.
    @ObservableState
    struct State: Equatable {
        var currentUser: AppUser
        /// Activity log entries used to compute in-plan KPIs.
        var activityEntries: [UserActivityEntry] = []
        /// Previously completed plan periods shown in the history section.
        var planHistory: [UserPlanHistoryEntry] = []
        var path: StackState<Path.State> = StackState()
        /// Controls visibility of the logout confirmation dialog.
        var showLogoutConfirm: Bool = false

        // Permissions (resolved at onLoad)
        var canViewSales: Bool = false
        var canViewUsers: Bool = false
        var canManagePlans: Bool = false

        /// - Parameter currentUser: The authenticated user whose profile is displayed.
        init(currentUser: AppUser) {
            self.currentUser = currentUser
        }

        /// Number of salons visited within the active plan period.
        var salonsInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate }.count
        }

        /// Number of test-drive activities recorded within the active plan period.
        var testDrivesInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate && $0.status == .testDrive }.count
        }

        /// Number of salons first contacted during the active plan period (not previously contacted before the plan started).
        var newClientsInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            let contactedStatuses: Set<SalonStatus> = [.contacted, .testDrive, .demoScheduled, .ordered]
            let prePlanContacted = Set(
                activityEntries
                    .filter { $0.timestamp < plan.startDate && contactedStatuses.contains($0.status) }
                    .map(\.salonId)
            )
            let inPlanContacted = Set(
                activityEntries
                    .filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate && contactedStatuses.contains($0.status) }
                    .map(\.salonId)
            )
            return inPlanContacted.filter { !prePlanContacted.contains($0) }.count
        }

        /// Number of salons re-contacted during the active plan period that were already contacted before it started.
        var returningClientsInPlan: Int {
            guard let plan = currentUser.activePlan else { return 0 }
            let contactedStatuses: Set<SalonStatus> = [.contacted, .testDrive, .demoScheduled, .ordered]
            let prePlanContacted = Set(
                activityEntries
                    .filter { $0.timestamp < plan.startDate && contactedStatuses.contains($0.status) }
                    .map(\.salonId)
            )
            let inPlanContacted = Set(
                activityEntries
                    .filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate && contactedStatuses.contains($0.status) }
                    .map(\.salonId)
            )
            return inPlanContacted.filter { prePlanContacted.contains($0) }.count
        }
    }

    // MARK: - Action

    /// Actions dispatched by the profile screen and its sub-navigation.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Loads permissions, refreshes the current user, and fetches activity and plan history.
        case onLoad
        case userRefreshed(AppUser?)
        case activityLoaded([UserActivityEntry])
        case planHistoryLoaded([UserPlanHistoryEntry])
        /// Shows the logout confirmation dialog.
        case logoutTapped
        /// Signs out the current user after confirmation.
        case logoutConfirmed
        case navigateToActivity
        case navigateToSales
        case navigateToUsers
        /// Navigates to the full ranked-clients list, built from cached FlexiBee invoices.
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
                    await send(.userRefreshed(refreshed))
                    let hasPlan = refreshed?.activePlan != nil
                    if hasPlan {
                        let entries = (try? await firebase.fetchUserActivity(userId)) ?? []
                        await send(.activityLoaded(entries))
                    }
                    let history = (try? await firebase.fetchPlanHistory(userId)) ?? []
                    await send(.planHistoryLoaded(history))
                }

            case let .userRefreshed(user):
                if let user { state.currentUser = user }
                return .none

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

