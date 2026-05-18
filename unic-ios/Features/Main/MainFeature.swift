import ComposableArchitecture
import Foundation

// MARK: - AppPath

/// Single navigation path shared across all tabs; owned by MainFeature so the root
/// NavigationStack in MainView wraps TabView and provides smooth tab-bar animation on iOS 18+.
@Reducer
enum AppPath {
    case salonDetail(SalonDetailFeature)
    case testDrive(TestDriveFeature)
    case productDetail(ProductDetailFeature)
    case catalog(CatalogFeature)
    case userActivity(UserActivityFeature)
    case sales(SalesFeature)
    case invoiceDetail(InvoiceDetailFeature)
    case allTopClients(AllTopClientsFeature)
    case allTopProducts(AllTopProductsFeature)
    case users(UsersFeature)
    case plans(PlansFeature)
    case clientDetail(ClientDetailFeature)
}

extension AppPath.State: Equatable {}

// MARK: - MainFeature

/// Root TCA reducer for the authenticated main-app experience, composing the four primary tab reducers
/// (Salons, Promos, Stock, Profile) and the floating `PlanBannerFeature` overlay.
///
/// Owns the single root `AppPath` navigation stack used by all tabs.
///
/// **Navigation flows (cross-tab)**
/// Child features (SalonsFeature, StockFeature, ProfileFeature) send `.delegate(.navigate(pathState))`
/// actions which MainFeature intercepts to append the destination onto `state.path`.
///
/// **Sales sub-navigation (all handled here)**
/// - `.sales(.invoiceTapped)` → push `.invoiceDetail`
/// - `.sales(.seeAllTopClientsTapped)` → push `.allTopClients`
/// - `.sales(.seeAllTopProductsTapped)` → push `.allTopProducts`
/// - `.sales(.clientTapped)` → push `.clientDetail`
/// - `.invoiceDetail(.deleteCompleted)` → pop + force FlexiBee sync
/// - `.invoiceDetail(.productTapped)` → push `.productDetail`
/// - `.invoiceDetail(.clientTapped)` → push `.clientDetail`
/// - `.allTopClients(.clientTapped)` → push `.clientDetail`
/// - `.allTopProducts(.productTapped)` → push `.productDetail`
/// - `.clientDetail(.invoiceTapped)` → push `.invoiceDetail`
/// - `.users(.userTapped)` → push `.userActivity`
/// - `.testDrive(.salonTapped)` → push `.salonDetail`
/// - `.salonDetail(.salonUpdated)` → forwards `.salons(.salonSaved)`
/// - `.salonDetail(.statusAdded)` → forwards `.salons(.salonSaved)`
/// - `.salonDetail(.deleteFinished)` → forwards `.salons(.salonDeleted)`
@Reducer
struct MainFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .salons
        var currentUser: AppUser
        var salons = SalonsFeature.State()
        var promos = PromosFeature.State()
        var stock = StockFeature.State()
        var profile: ProfileFeature.State
        var planBanner = PlanBannerFeature.State()
        var path: StackState<AppPath.State> = StackState()

        enum Tab: String, Equatable, Hashable, CaseIterable { case salons, promos, stock, profile }

        init(currentUser: AppUser, preloadedSalons: IdentifiedArrayOf<Salon> = []) {
            self.currentUser = currentUser
            self.profile = ProfileFeature.State(currentUser: currentUser)
            if !preloadedSalons.isEmpty {
                self.salons.salons = preloadedSalons
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case salons(SalonsFeature.Action)
        case promos(PromosFeature.Action)
        case stock(StockFeature.Action)
        case profile(ProfileFeature.Action)
        case planBanner(PlanBannerFeature.Action)
        case path(StackActionOf<AppPath>)
        case onAppear
    }

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        BindingReducer()
        Scope(state: \.salons, action: \.salons) { SalonsFeature() }
        Scope(state: \.promos, action: \.promos) { PromosFeature() }
        Scope(state: \.stock, action: \.stock) { StockFeature() }
        Scope(state: \.profile, action: \.profile) { ProfileFeature() }
        Scope(state: \.planBanner, action: \.planBanner) { PlanBannerFeature() }
        Reduce { state, action in
            switch action {

            case .onAppear:
                return .none

            // MARK: - Salons navigation

            case .salons(.delegate(.navigate(let pathState))):
                state.path.append(pathState)
                return .none

            case .path(.element(_, .testDrive(.salonTapped(let salon)))):
                state.path.append(.salonDetail(SalonDetailFeature.State(salon: salon)))
                return .none

            case .path(.element(_, .salonDetail(.salonUpdated(let salon)))):
                return .send(.salons(.salonSaved(salon)))

            case .path(.element(_, .salonDetail(.statusAdded(_)))):
                if let last = state.path.last, case let .salonDetail(detail) = last {
                    return .send(.salons(.salonSaved(detail.salon)))
                }
                return .none

            case .path(.element(_, .salonDetail(.deleteFinished))):
                if let last = state.path.last, case let .salonDetail(detail) = last {
                    return .send(.salons(.salonDeleted(detail.salon.salonId)))
                }
                return .none

            // MARK: - Stock navigation

            case .stock(.delegate(.navigate(let pathState))):
                state.path.append(pathState)
                return .none

            // MARK: - Profile navigation

            case .profile(.delegate(.navigate(let pathState))):
                state.path.append(pathState)
                return .none

            // MARK: - Sales sub-navigation (flat stack)

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
                return .run { [flexiBeeClient] _ in
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

            case .binding, .salons, .promos, .stock, .profile, .planBanner:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
