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
///   1. Calls `auth.refreshCurrentUser()` → `.userRefreshed`.
///   2. Calls `firebase.fetchCurrentPlan(userId)` → `.planLoaded` (latest `planHistory` entry).
///   3. If a plan exists, fetches `firebase.fetchUserActivity(userId)` → `.activityLoaded`.
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

    // MARK: - State

    /// State for the profile tab and its navigation stack.
    @ObservableState
    struct State: Equatable {
        var currentUser: AppUser
        /// The most recent plan entry fetched from the user's `planHistory` subcollection.
        var activePlan: UserActivePlan?
        /// Activity log entries used to compute in-plan KPIs.
        var activityEntries: [UserActivityEntry] = []
        /// `true` while activity entries are being fetched from Firebase.
        var isLoadingActivity: Bool = false
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
            guard let plan = activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate }.count
        }

        /// Number of test-drive activities recorded within the active plan period.
        var testDrivesInPlan: Int {
            guard let plan = activePlan else { return 0 }
            return activityEntries.filter { $0.timestamp >= plan.startDate && $0.timestamp <= plan.endDate && $0.status == .testDrive }.count
        }

        /// Number of salons first contacted during the active plan period (not previously contacted before the plan started).
        var newClientsInPlan: Int {
            guard let plan = activePlan else { return 0 }
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
            guard let plan = activePlan else { return 0 }
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

        /// Number of salons visited today (only meaningful while the plan is active).
        var salonsToday: Int {
            guard let plan = activePlan, plan.isActive else { return 0 }
            @Dependency(\.date) var date
            let startOfDay = Calendar.current.startOfDay(for: date())
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
            return activityEntries.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }.count
        }

        /// Number of test-drive activities recorded today (only meaningful while the plan is active).
        var testDrivesToday: Int {
            guard let plan = activePlan, plan.isActive else { return 0 }
            @Dependency(\.date) var date
            let startOfDay = Calendar.current.startOfDay(for: date())
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
            return activityEntries.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay && $0.status == .testDrive }.count
        }
    }

    // MARK: - Action

    /// Actions dispatched by the profile screen and its sub-navigation.
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Loads permissions, refreshes the current user, and fetches the current plan, activity, and plan history.
        case onLoad
        case userRefreshed(AppUser?)
        case planLoaded(UserActivePlan?)
        case activityLoadingStarted
        case activityLoaded([UserActivityEntry])
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
        case delegate(Delegate)

        enum Delegate: Equatable {
            case navigate(AppPath.State)
        }
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
                    let currentPlan = try? await firebase.fetchCurrentPlan(userId)
                    await send(.planLoaded(currentPlan))
                    if currentPlan != nil {
                        await send(.activityLoadingStarted)
                        let entries = (try? await firebase.fetchUserActivity(userId)) ?? []
                        await send(.activityLoaded(entries))
                    }
                }

            case let .userRefreshed(user):
                if let user { state.currentUser = user }
                return .none

            case let .planLoaded(plan):
                state.activePlan = plan
                return .none

            case .activityLoadingStarted:
                state.isLoadingActivity = true
                return .none

            case let .activityLoaded(entries):
                state.activityEntries = entries
                state.isLoadingActivity = false
                return .none

            case .logoutTapped:
                state.showLogoutConfirm = true
                return .none

            case .logoutConfirmed:
                state.showLogoutConfirm = false
                auth.logout()
                return .none

            case .navigateToActivity:
                return .send(.delegate(.navigate(.userActivity(UserActivityFeature.State(user: state.currentUser)))))

            case .navigateToSales:
                guard state.canViewSales else { return .none }
                return .send(.delegate(.navigate(.sales(SalesFeature.State()))))

            case .navigateToUsers:
                guard state.canViewUsers else { return .none }
                return .send(.delegate(.navigate(.users(UsersFeature.State()))))

            case .navigateToClients:
                guard state.canViewSales else { return .none }
                let allInvoices = flexiBeeClient.invoices()
                let clients = Dictionary(grouping: allInvoices) { $0.clientName }
                    .map { (name: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
                    .sorted { $0.revenue > $1.revenue }
                return .send(.delegate(.navigate(.allTopClients(AllTopClientsFeature.State(clients: clients)))))

            case .navigateToPlans:
                guard state.canManagePlans else { return .none }
                return .send(.delegate(.navigate(.plans(PlansFeature.State()))))

            case .delegate:
                return .none

            case .binding:
                return .none
            }
        }
    }
}

