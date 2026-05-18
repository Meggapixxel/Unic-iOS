// FILE: unic-ios/Features/Sales/SalesFeature.swift
import ComposableArchitecture
import Foundation

// MARK: - Monthly Revenue Model

/// A single data point used to plot monthly revenue on a chart.
struct MonthlyRevenuePoint: Identifiable, Equatable {
    let id = UUID()
    /// Short month label displayed on the chart axis (e.g. "Jan").
    let label: String
    /// First day of the month this point represents.
    let month: Date
    /// Total invoice revenue for the month.
    let revenue: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sales Feature

/// Manages the Sales tab, which surfaces two complementary views of FlexiBee invoice data:
/// a searchable/filterable invoice list and an analytics dashboard (revenue chart, top clients,
/// top products) scoped to a navigable month or year period.
///
/// ## Entry point
/// `onLoad` is dispatched by the parent (`ProfileFeature`) when the Sales tab first appears.
/// It immediately hydrates state from the in-memory FlexiBee cache and then calls
/// `flexiBeeClient.loadIfNeeded()` to fetch fresh data from the network if the cache is stale.
///
/// ## Key action flows
///
/// - **`onLoad`** — Reads cached invoices, movement items, and stock names synchronously, then
///   fires a background task that awaits `loadIfNeeded()` and dispatches `syncCompleted` plus
///   `binding` actions to update movements and the stock-name lookup dictionary.
///
/// - **`forceSync`** — Triggered by a pull-to-refresh gesture. Sets `isLoading = true`, calls
///   `flexiBeeClient.forceSync()` to bypass the cache, then dispatches `syncCompleted` and
///   refreshes movement/stock data identically to `onLoad`.
///
/// - **`syncCompleted`** — Lands updated invoices and the last-sync timestamp; clears the
///   loading indicator. All computed analytics properties (`totalRevenue`, `topClients`,
///   `topProducts`, `monthlyRevenue`, etc.) recompute automatically from `allInvoices`.
///
/// - **`goToPrevPeriod` / `goToNextPeriod`** — Shift `selectedDate` by one month or year.
///   Forward navigation is gated by `canGoNext` so users cannot scroll past today.
///   The `periodChanged` action switches between `.month` and `.year` granularity.
///
/// - **`createInvoiceTapped`** — Presents the `.createInvoice` destination sheet backed by
///   `InvoiceFormPlaceholderFeature`.
///
/// - **`invoiceCreated`** — Dismisses the sheet, triggers `forceSync`, then dispatches
///   `invoiceTapped` for the newly created invoice so the parent can push the detail screen.
///
/// - **`destination(.presented(.createInvoice(.dismiss)))`** — Handles the sheet being closed
///   without a submission: dismisses the destination and force-syncs to pick up any server-side
///   saves.
///
/// - **`invoiceTapped`, `seeAllTopClientsTapped`, `seeAllTopProductsTapped`, `clientTapped`** —
///   No-op within this reducer; all navigation for these is delegated upward to
///   `ProfileFeature` via action bubbling.
///
/// ## Navigation
/// The only `Destination` sheet owned by this reducer is `.createInvoice(InvoiceFormPlaceholderFeature)`,
/// which hosts the invoice creation UI. Invoice detail, client detail, and top-list drill-downs
/// are pushed via `ProfileFeature`'s `@Reducer enum Path`.
///
/// ## Side effects
/// - `flexiBeeClient.loadIfNeeded()` — conditional network sync on first load.
/// - `flexiBeeClient.forceSync()` — unconditional full refresh on pull-to-refresh or after
///   a successful invoice creation/dismissal.
/// - All FlexiBee reads (`invoices()`, `salesMovementItems()`, `stockWithPrices()`) run on
///   `MainActor` via `MainActor.run` inside `.run` effects to satisfy Swift 6 concurrency rules.
@Reducer
struct SalesFeature {
    /// Observable state for the Sales tab.
    @ObservableState
    struct State: Equatable {
        /// Currently active tab segment (invoices vs. analytics).
        var section: SalesSection = .invoices
        /// Aggregation period for analytics (month or year).
        var period: SalesPeriod = .year
        /// The reference date used to compute the current analytics period.
        var selectedDate: Date
        /// Today's date, used to cap forward navigation.
        var today: Date
        var searchText: String = ""
        /// Active payment-status filter; `nil` means all statuses.
        var statusFilter: PaymentStatus?
        var isLoading: Bool = false
        var lastSyncDate: Date?
        @Presents var destination: Destination.State?

        // Backing data
        /// All issued invoices, loaded from cache or network.
        var allInvoices: [FlexiBeeInvoice] = []
        /// All warehouse outflow movement items used for top-products analytics.
        var allMovementItems: [FlexiBeeStockMovementItem] = []
        /// Maps article code → product name for movement items that lack a full name.
        var stockNameLookup: [String: String] = [:]

        init() {
            @Dependency(\.date) var date
            let now = date()
            self.selectedDate = now
            self.today = now
        }

        // MARK: Computed — period analytics

        /// Invoices whose issue date falls within the current analytics period.
        var periodInvoices: [FlexiBeeInvoice] {
            let (from, to) = period.dateRange(for: selectedDate)
            return allInvoices.filter {
                guard let d = $0.issueDate else { return false }
                return d >= from && d <= to
            }
        }

        /// All invoices filtered by search text and the active status filter (not period-bounded).
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

        /// Sum of all invoice totals in the selected period.
        var totalRevenue: Double { periodInvoices.reduce(0) { $0 + $1.total } }
        /// Sum of totals for invoices with `.paid` status in the selected period.
        var paidRevenue: Double { periodInvoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total } }
        /// Sum of totals for unpaid and overdue invoices in the selected period.
        var unpaidRevenue: Double {
            periodInvoices.filter {
                $0.paymentStatus == .unpaid || $0.paymentStatus == .overdue
            }.reduce(0) { $0 + $1.total }
        }
        /// Number of overdue invoices in the selected period.
        var overdueCount: Int { periodInvoices.filter { $0.paymentStatus == .overdue }.count }

        /// Clients ranked by total invoice revenue descending in the selected period.
        var topClients: [(name: String, revenue: Double)] {
            Dictionary(grouping: periodInvoices) { $0.clientName }
                .map { (name: $0.key, revenue: $0.value.reduce(0) { $0 + $1.total }) }
                .sorted { $0.revenue > $1.revenue }
        }

        /// Products ranked by total quantity issued from warehouse in the selected period.
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
                    let name = stockNameLookup[code] ?? items.first?.productName ?? code
                    return (code: code, name: name, quantity: qty)
                }
                .sorted { $0.quantity > $1.quantity }
        }

        private static let monthFmt: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale.current; f.dateFormat = "MMM"; return f
        }()

        /// Revenue grouped by month within the selected period, sorted chronologically.
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

        /// `true` when there is at least one invoice in the currently selected period.
        var hasPeriodData: Bool { !periodInvoices.isEmpty }

        /// Formatted label for the period navigation header (e.g. "May 2026" or "2026").
        var periodLabel: String {
            switch period {
            case .month: return Self.monthYearFmt.string(from: selectedDate)
            case .year:  return String(Calendar.current.component(.year, from: selectedDate))
            }
        }

        /// `true` when the user can navigate forward to the next period (not already at the current period).
        var canGoNext: Bool {
            let cal = Calendar.current
            let gran: Calendar.Component = period == .month ? .month : .year
            return !cal.isDate(selectedDate, equalTo: today, toGranularity: gran)
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
        case clientTapped(String)
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
                state.stockNameLookup = Dictionary(
                    uniqueKeysWithValues: flexiBeeClient.stockWithPrices().map { ($0.code, $0.productName) }
                )
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.loadIfNeeded()
                    let (invoices, movements, stock, syncDate) = await MainActor.run {
                        (flexiBeeClient.invoices(), flexiBeeClient.salesMovementItems(), flexiBeeClient.stockWithPrices(), flexiBeeClient.lastSyncDate())
                    }
                    await send(.syncCompleted(invoices, syncDate))
                    await send(.binding(.set(\.allMovementItems, movements)))
                    await send(.binding(.set(\.stockNameLookup, Dictionary(uniqueKeysWithValues: stock.map { ($0.code, $0.productName) }))))
                }

            case .forceSync:
                state.isLoading = true
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                    let (invoices, movements, stock, syncDate) = await MainActor.run {
                        (flexiBeeClient.invoices(), flexiBeeClient.salesMovementItems(), flexiBeeClient.stockWithPrices(), flexiBeeClient.lastSyncDate())
                    }
                    await send(.syncCompleted(invoices, syncDate))
                    await send(.binding(.set(\.allMovementItems, movements)))
                    await send(.binding(.set(\.stockNameLookup, Dictionary(uniqueKeysWithValues: stock.map { ($0.code, $0.productName) }))))
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

            case .clientTapped:
                // Navigation handled by parent (ProfileFeature)
                return .none

            case .destination(.presented(.createInvoice(.dismiss))):
                state.destination = nil
                state.isLoading = true
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    await flexiBeeClient.forceSync()
                    let (invoices, syncDate) = await MainActor.run {
                        (flexiBeeClient.invoices(), flexiBeeClient.lastSyncDate())
                    }
                    await send(.syncCompleted(invoices, syncDate))
                }

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

/// Lightweight TCA leaf that carries context for the invoice create/edit sheet until a full form reducer is implemented.
@Reducer
struct InvoiceFormPlaceholderFeature {
    /// State passed into the invoice form sheet.
    @ObservableState
    struct State: Equatable {
        /// When non-nil, the form opens in edit mode for this invoice.
        var editingInvoice: FlexiBeeInvoice? = nil
        /// When non-nil, the client picker is pre-populated with this code.
        var preSelectClientCode: String? = nil
    }

    enum Action {
        case dismiss
        case submitted(FlexiBeeInvoice)
    }

    var body: some Reducer<State, Action> {
        Reduce { _, _ in .none }
    }
}

// MARK: - AllTopProductsFeature

/// TCA reducer for the "See All Top Products" drill-down list with search filtering.
@Reducer
struct AllTopProductsFeature {
    /// Observable state for the full top-products list.
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var products: [(code: String, name: String, quantity: Double)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.searchText == rhs.searchText &&
            lhs.products.map(\.code) == rhs.products.map(\.code)
        }

        /// Products filtered by the current search text.
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

/// TCA reducer for the "See All Top Clients" drill-down list with search filtering.
@Reducer
struct AllTopClientsFeature {
    /// Observable state for the full top-clients list.
    @ObservableState
    struct State: Equatable {
        var searchText: String = ""
        var clients: [(name: String, revenue: Double)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.searchText == rhs.searchText &&
            lhs.clients.map(\.name) == rhs.clients.map(\.name)
        }

        /// Clients filtered by the current search text.
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

/// TCA reducer for the client detail screen, showing invoice history and summary stats,
/// with support for creating new invoices and editing the client record.
@Reducer
struct ClientDetailFeature {

    @Reducer
    enum Destination {
        case createInvoice(InvoiceFormPlaceholderFeature)
        case editClient(ClientEditFeature)
    }

    /// Observable state for the client detail screen.
    @ObservableState
    struct State: Equatable {
        var clientName: String
        /// Short FlexiBee address-book code, used to fetch firm details and filter invoices.
        var clientCode: String?
        /// Tax identification number (IČ), loaded asynchronously.
        var clientIc: String? = nil
        /// VAT number (DIČ), loaded asynchronously.
        var clientDic: String? = nil
        /// Whether the current user may create invoices.
        var canEdit: Bool = false
        /// Whether the current user may edit client records.
        var canEditClient: Bool = false
        /// All invoices belonging to this client.
        var invoices: [FlexiBeeInvoice]
        @Presents var destination: Destination.State?

        /// Lifetime revenue across all invoices for this client.
        var totalRevenue:  Double { invoices.reduce(0) { $0 + $1.total } }
        /// Revenue from fully paid invoices.
        var paidRevenue:   Double { invoices.filter { $0.paymentStatus == .paid }.reduce(0) { $0 + $1.total } }
        /// Revenue from unpaid and partially-paid invoices.
        var unpaidRevenue: Double { invoices.filter { $0.paymentStatus == .unpaid || $0.paymentStatus == .partial }.reduce(0) { $0 + $1.total } }
        /// Revenue from overdue invoices.
        var overdueRevenue: Double { invoices.filter { $0.paymentStatus == .overdue }.reduce(0) { $0 + $1.total } }
        /// Number of overdue invoices.
        var overdueCount:  Int    { invoices.filter { $0.paymentStatus == .overdue }.count }

        /// Date of the client's earliest invoice, or `nil` when unavailable.
        var firstOrderDate: Date? { invoices.compactMap(\.issueDate).min() }
        /// Date of the client's most recent invoice, or `nil` when unavailable.
        var lastOrderDate:  Date? { invoices.compactMap(\.issueDate).max() }

        /// Invoices sorted newest-first.
        var sortedInvoices: [FlexiBeeInvoice] {
            invoices.sorted { ($0.issueDate ?? .distantPast) > ($1.issueDate ?? .distantPast) }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.clientName == rhs.clientName &&
            lhs.clientCode == rhs.clientCode &&
            lhs.clientIc == rhs.clientIc &&
            lhs.clientDic == rhs.clientDic &&
            lhs.canEdit == rhs.canEdit &&
            lhs.canEditClient == rhs.canEditClient &&
            lhs.invoices.map(\.id) == rhs.invoices.map(\.id) &&
            lhs.destination == rhs.destination
        }
    }

    enum Action {
        case onLoad
        case firmLoaded(FlexiBeeFirm?)
        case invoiceTapped(FlexiBeeInvoice)
        case newInvoiceTapped
        case editClientTapped
        case editClientFetched(FlexiBeeFirm?)
        case destination(PresentationAction<Destination.Action>)
    }

    @Dependency(\.flexiBeeClient) var flexiBeeClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onLoad:
                guard let code = state.clientCode else { return .none }
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    let firm = try? await flexiBeeClient.fetchFirm(code)
                    await send(.firmLoaded(firm))
                }

            case let .firmLoaded(firm):
                state.clientIc  = firm?.ic?.nilIfEmpty
                state.clientDic = firm?.dic?.nilIfEmpty
                return .none
            case .newInvoiceTapped:
                state.destination = .createInvoice(
                    InvoiceFormPlaceholderFeature.State(preSelectClientCode: state.clientCode)
                )
                return .none
            case .editClientTapped:
                guard let code = state.clientCode else { return .none }
                let flexiBeeClient = flexiBeeClient
                return .run { [flexiBeeClient] send in
                    let firm = try? await flexiBeeClient.fetchFirm(code)
                    await send(.editClientFetched(firm))
                }
            case let .editClientFetched(firm):
                let code = state.clientCode ?? ""
                state.destination = .editClient(ClientEditFeature.State(
                    firmCode: code,
                    name:  firm?.name  ?? state.clientName,
                    ic:    firm?.ic    ?? "",
                    dic:   firm?.dic   ?? "",
                    email: firm?.email ?? "",
                    phone: firm?.phone ?? ""
                ))
                return .none
            case .invoiceTapped:
                return .none
            case .destination(.presented(.createInvoice(.dismiss))):
                state.destination = nil
                let name = state.clientName
                let code = state.clientCode
                let allInvoices = flexiBeeClient.invoices()
                state.invoices = allInvoices.filter {
                    code != nil ? $0.clientCode == code : $0.clientName == name
                }
                return .none
            case .destination(.presented(.editClient(.dismiss))):
                if case let .editClient(s) = state.destination {
                    state.clientName = s.name.trimmingCharacters(in: .whitespaces)
                    state.clientIc = s.ic.isEmpty ? nil : s.ic
                    state.clientDic = s.dic.isEmpty ? nil : s.dic
                }
                state.destination = nil
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension ClientDetailFeature.Destination.State: Equatable {}

extension SalesFeature.Destination.State: Equatable {}

// MARK: - ClientEditFeature

/// TCA reducer for the inline client-edit form that updates a FlexiBee address-book entry.
@Reducer
struct ClientEditFeature {
    /// Observable state for the client edit form.
    @ObservableState
    struct State: Equatable {
        /// Short FlexiBee code identifying the firm to update.
        var firmCode: String
        var name: String
        var ic: String
        var dic: String
        var email: String
        var phone: String
        /// `true` while the network PUT request is in flight.
        var isSubmitting: Bool = false
        /// Non-nil when the submit request fails.
        var errorMessage: String? = nil

        /// Returns `true` when the name field contains at least one non-whitespace character.
        var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case submitTapped
        case submitCompleted(Result<Void, Error>)
        case dismiss
    }

    @Dependency(\.flexiBeeClient) var flexiBeeClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .submitTapped:
                guard state.isValid else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                let code = state.firmCode
                let firm = NewFirm(
                    name:  state.name.trimmingCharacters(in: .whitespaces),
                    ic:    state.ic.nilIfEmpty,
                    dic:   state.dic.nilIfEmpty,
                    email: state.email.nilIfEmpty,
                    phone: state.phone.nilIfEmpty
                )
                return .run { [flexiBeeClient] send in
                    do {
                        try await flexiBeeClient.updateFirm(code, firm)
                        await send(.submitCompleted(.success(())))
                    } catch {
                        await send(.submitCompleted(.failure(error)))
                    }
                }
            case .submitCompleted(.success):
                state.isSubmitting = false
                return .send(.dismiss)
            case let .submitCompleted(.failure(err)):
                state.isSubmitting = false
                state.errorMessage = err.localizedDescription
                return .none
            case .dismiss:
                return .none
            case .binding:
                return .none
            }
        }
    }
}
