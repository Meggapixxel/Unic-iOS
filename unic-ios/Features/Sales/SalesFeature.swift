// FILE: unic-ios/Features/Sales/SalesFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Monthly Revenue Model

struct MonthlyRevenuePoint: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let month: Date
    let revenue: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sales Feature

@Reducer
struct SalesFeature {
    @ObservableState
    struct State: Equatable {
        var section: SalesSection = .invoices
        var period: SalesPeriod = .year
        var selectedDate: Date = Date()
        var searchText: String = ""
        var statusFilter: PaymentStatus?
        var isLoading: Bool = false
        var lastSyncDate: Date?
        @Presents var destination: Destination.State?

        // Backing data
        var allInvoices: [FlexiBeeInvoice] = []
        var allMovementItems: [FlexiBeeStockMovementItem] = []

        // MARK: Computed — period analytics

        var periodInvoices: [FlexiBeeInvoice] {
            let (from, to) = period.dateRange(for: selectedDate)
            return allInvoices.filter {
                guard let d = $0.issueDate else { return false }
                return d >= from && d <= to
            }
        }

        var filteredInvoices: [FlexiBeeInvoice] {
            var result = allInvoices
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                result = result.filter {
                    $0.invoiceNumber.lowercased().contains(q) ||
                    $0.clientName.lowercased().contains(q)
                }
            }
            if let s = statusFilter {
                result = result.filter { $0.paymentStatus == s }
            }
            return result
        }

        var totalRevenue: Double { periodInvoices.reduce(0) { $0 + $1.total } }
        var paidRevenue: Double { periodInvoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total } }
        var unpaidRevenue: Double {
            periodInvoices.filter {
                $0.paymentStatus == .unpaid || $0.paymentStatus == .overdue
            }.reduce(0) { $0 + $1.total }
        }
        var overdueCount: Int { periodInvoices.filter { $0.paymentStatus == .overdue }.count }

        var topClients: [(name: String, revenue: Double)] {
            Dictionary(grouping: periodInvoices) { $0.clientName }
                .map { (name: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
                .sorted { $0.revenue > $1.revenue }
        }

        var topProducts: [(code: String, name: String, quantity: Double)] {
            let (from, to) = period.dateRange(for: selectedDate)
            let inPeriod = allMovementItems.filter {
                guard let d = $0.date else { return false }
                return d >= from && d <= to
            }
            return Dictionary(grouping: inPeriod, by: { $0.productCode })
                .compactMap { code, items -> (code: String, name: String, quantity: Double)? in
                    guard !code.isEmpty else { return nil }
                    let qty = items.reduce(0) { $0 + $1.quantityIssued }
                    let name = items.first?.productName ?? code
                    return (code: code, name: name, quantity: qty)
                }
                .sorted { $0.quantity > $1.quantity }
        }

        private static let monthFmt: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale.current; f.dateFormat = "MMM"; return f
        }()

        var monthlyRevenue: [MonthlyRevenuePoint] {
            let cal = Calendar.current
            let (from, _) = period.dateRange(for: selectedDate)
            let grouped = Dictionary(grouping: periodInvoices) { (inv: FlexiBeeInvoice) -> Date in
                guard let d = inv.issueDate else { return from }
                return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? from
            }
            return grouped
                .map {
                    MonthlyRevenuePoint(
                        label: Self.monthFmt.string(from: $0.key),
                        month: $0.key,
                        revenue: $0.value.reduce(0) { $0 + $1.total }
                    )
                }
                .sorted { $0.month < $1.month }
        }

        var hasPeriodData: Bool { !periodInvoices.isEmpty }

        var periodLabel: String {
            switch period {
            case .month: return Self.monthYearFmt.string(from: selectedDate)
            case .year:  return String(Calendar.current.component(.year, from: selectedDate))
            }
        }

        var canGoNext: Bool {
            let cal = Calendar.current
            let gran: Calendar.Component = period == .month ? .month : .year
            return !cal.isDate(selectedDate, equalTo: Date(), toGranularity: gran)
        }

        private static let monthYearFmt: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale.current; f.dateFormat = "LLLL yyyy"; return f
        }()
    }

    // MARK: - Destination

    @Reducer
    enum Destination {
        case createInvoice(InvoiceFormPlaceholderFeature)
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case syncCompleted([FlexiBeeInvoice], Date?)
        case sectionChanged(SalesSection)
        case periodChanged(SalesPeriod)
        case dateChanged(Date)
        case searchTextChanged(String)
        case statusFilterChanged(PaymentStatus?)
        case forceSync
        case goToPrevPeriod
        case goToNextPeriod
        case createInvoiceTapped
        case invoiceCreated(FlexiBeeInvoice)
        case invoiceTapped(FlexiBeeInvoice)
        case seeAllTopClientsTapped
        case seeAllTopProductsTapped
        case destination(PresentationAction<Destination.Action>)
        case failed(String)
    }

    // MARK: - Dependencies

    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.date) var date

    // MARK: - Body

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {

            case .onLoad:
                state.isLoading = flexiBeeClient.isLoading()
                state.lastSyncDate = flexiBeeClient.lastSyncDate()
                let cached = flexiBeeClient.invoices()
                if !cached.isEmpty {
                    state.allInvoices = cached
                    state.allMovementItems = flexiBeeClient.salesMovementItems()
                }
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.loadIfNeeded()
                    let (invoices, movements, syncDate) = await MainActor.run {
                        (flexiBeeClient.invoices(), flexiBeeClient.salesMovementItems(), flexiBeeClient.lastSyncDate())
                    }
                    await send(.syncCompleted(invoices, syncDate))
                    await send(.binding(.set(\.allMovementItems, movements)))
                }

            case .forceSync:
                state.isLoading = true
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                    let (invoices, movements, syncDate) = await MainActor.run {
                        (flexiBeeClient.invoices(), flexiBeeClient.salesMovementItems(), flexiBeeClient.lastSyncDate())
                    }
                    await send(.syncCompleted(invoices, syncDate))
                    await send(.binding(.set(\.allMovementItems, movements)))
                }

            case let .syncCompleted(invoices, date):
                state.isLoading = false
                state.allInvoices = invoices
                state.lastSyncDate = date
                return .none

            case let .sectionChanged(section):
                state.section = section
                return .none

            case let .periodChanged(period):
                state.period = period
                return .none

            case let .dateChanged(date):
                state.selectedDate = date
                return .none

            case let .searchTextChanged(text):
                state.searchText = text
                return .none

            case let .statusFilterChanged(status):
                state.statusFilter = status
                return .none

            case .goToPrevPeriod:
                let component: Calendar.Component = state.period == .month ? .month : .year
                state.selectedDate = Calendar.current.date(
                    byAdding: component, value: -1, to: state.selectedDate
                ) ?? state.selectedDate
                return .none

            case .goToNextPeriod:
                guard state.canGoNext else { return .none }
                let cal = Calendar.current
                let component: Calendar.Component = state.period == .month ? .month : .year
                let now = date()
                let next = cal.date(byAdding: component, value: 1, to: state.selectedDate) ?? state.selectedDate
                state.selectedDate = cal.isDate(next, equalTo: now, toGranularity: component) ? now : next
                return .none

            case .createInvoiceTapped:
                state.destination = .createInvoice(InvoiceFormPlaceholderFeature.State())
                return .none

            case let .invoiceCreated(invoice):
                state.destination = nil
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                    let (invoices, syncDate) = await MainActor.run { (flexiBeeClient.invoices(), flexiBeeClient.lastSyncDate()) }
                    await send(.syncCompleted(invoices, syncDate))
                    if let created = invoices.first(where: { $0.id == invoice.id }) {
                        await send(.invoiceTapped(created))
                    }
                }

            case .invoiceTapped:
                // Navigation handled by parent (ProfileFeature)
                return .none

            case .seeAllTopClientsTapped:
                // Navigation handled by parent (ProfileFeature)
                return .none

            case .seeAllTopProductsTapped:
                // Navigation handled by parent (ProfileFeature)
                return .none

            case .destination(.presented(.createInvoice(.dismiss))):
                state.destination = nil
                return .none

            case .destination:
                return .none

            case let .failed(msg):
                // Errors are handled in InvoiceDetailFeature
                _ = msg
                return .none

            case .binding:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - Placeholder sub-features (referenced from Destination/Path)
// InvoiceFormPlaceholderFeature is a lightweight leaf until a full TCA form feature is built.

@Reducer
struct InvoiceFormPlaceholderFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action {
        case dismiss
        case submitted(FlexiBeeInvoice)
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

// MARK: - AllTopProductsFeature

@Reducer
struct AllTopProductsFeature {
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var products: [(code: String, name: String, quantity: Double)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.searchText == rhs.searchText &&
            lhs.products.map(\.code) == rhs.products.map(\.code)
        }

        var filtered: [(code: String, name: String, quantity: Double)] {
            guard !searchText.isEmpty else { return products }
            let q = searchText.lowercased()
            return products.filter {
                $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case productTapped(String)
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { _, _ in .none }
    }
}

// MARK: - AllTopClientsFeature

@Reducer
struct AllTopClientsFeature {
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var clients: [(name: String, revenue: Double)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.searchText == rhs.searchText &&
            lhs.clients.map(\.name) == rhs.clients.map(\.name)
        }

        var filtered: [(name: String, revenue: Double)] {
            guard !searchText.isEmpty else { return clients }
            let q = searchText.lowercased()
            return clients.filter { $0.name.lowercased().contains(q) }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case clientTapped(String)
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { _, _ in .none }
    }
}

// MARK: - ClientDetailFeature

@Reducer
struct ClientDetailFeature {
    @ObservableState
    struct State: Equatable {
        var clientName: String
        var invoices: [FlexiBeeInvoice]

        var totalRevenue: Double { invoices.reduce(0) { $0 + $1.total } }
        var paidRevenue:  Double { invoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total } }
        var unpaidRevenue: Double { totalRevenue - paidRevenue }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.clientName == rhs.clientName &&
            lhs.invoices.map(\.id) == rhs.invoices.map(\.id)
        }
    }

    enum Action {
        case invoiceTapped(FlexiBeeInvoice)
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

extension SalesFeature.Destination.State: Equatable {}
