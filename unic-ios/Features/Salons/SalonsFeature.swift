// FILE: unic-ios/Features/Salons/SalonsFeature.swift

import ComposableArchitecture
import Foundation
import IdentifiedCollections

/// Manages the main salons list screen, providing search, multi-filter, sort, and map-toggle capabilities
/// alongside navigation to salon detail, test-drive, and route-planner screens.
///
/// **Entry point**
/// `.onLoad` is dispatched by the view's `.task` modifier (or equivalent). It is guarded so that a
/// second call while salons are already populated is a no-op, preventing redundant fetches when
/// navigating back from a child screen.
///
/// **Key action flows**
/// - `.onLoad` — fires two concurrent async calls: `fetchAllSalons()` and `loadWorksOnTags()`.
///   Salons are stored in `State.salons` via `.salonsLoaded`; tags are cached in the Firebase client.
/// - `.salonTapped(_)` — pushes a `SalonDetailFeature` onto the navigation stack.
/// - `.openAdd` — guarded by `auth.canEditSalon()`; presents the `SalonFormFeature` modal.
/// - `.salonSaved(_)` — upserts the salon into `State.salons`, dismisses the form sheet, and
///   propagates the updated value into any open `salonDetail` element already in the stack.
/// - `.salonDeleted(_)` — removes the salon from `State.salons` and pops the detail screen if it
///   is at the top of the navigation stack.
/// - `.clearFilters` — resets `languageFilter` and `dateRangeFilter` to empty sets.
/// - Binding actions for `searchText`, `statusFilter`, `sortOption`, `sortAscending`, `showMap`,
///   `showFilterPopover`, `showStatusInfo`, `languageFilter`, and `dateRangeFilter` all flow
///   through `BindingReducer`, causing `displayedSalons` and `statCounts` to recompute on the fly.
///
/// **Path propagation (child → parent)**
/// - `.path(.element(_, .testDrive(.salonTapped(_))))` — pushes a new `salonDetail` for the tapped
///   salon, allowing the test-drive list to act as a secondary entry point to detail.
/// - `.path(.element(_, .salonDetail(.salonUpdated(_))))` — forwards to `.salonSaved` to keep the
///   parent list in sync after an in-detail edit.
/// - `.path(.element(_, .salonDetail(.statusAdded(_))))` — reads the updated salon from the open
///   detail state and forwards to `.salonSaved`.
/// - `.path(.element(_, .salonDetail(.deleteFinished)))` — reads the salonId from the detail state
///   and forwards to `.salonDeleted`; the detail reducer has already called `@Dependency(\.dismiss)`.
///
/// **Navigation — `Path` destinations**
/// | Case | Trigger |
/// |---|---|
/// | `.salonDetail(SalonDetailFeature)` | `.salonTapped(_)` or test-drive `.salonTapped` |
/// | `.testDrive(TestDriveFeature)` | Pushed by the view (e.g. the test-drive toolbar button) |
/// | `.routePlanner(RoutePlannerFeature)` | Pushed by the view (e.g. the route-planner toolbar button) |
///
/// **Navigation — `Destination` sheet**
/// | Case | Trigger |
/// |---|---|
/// | `.form(SalonFormFeature)` | `.openAdd` (create flow) |
///
/// **Side effects**
/// - `firebase.fetchAllSalons()` — Firestore read; called once on load.
/// - `firebase.loadWorksOnTags()` — Firestore read; runs concurrently with the salons fetch on load.
/// - All filtering, searching, and sorting are pure computed properties — no async work.
@Reducer
struct SalonsFeature {

    // MARK: - Path

    /// Navigation stack destinations reachable from the salons list.
    @Reducer
    enum Path {
        case salonDetail(SalonDetailFeature)
        case testDrive(TestDriveFeature)
        case routePlanner(RoutePlannerFeature)
    }

    // MARK: - Destination

    /// Modal destinations presented from the salons list.
    @Reducer
    enum Destination {
        case form(SalonFormFeature)
    }

    // MARK: - State

    /// Observable state for the salons list screen.
    @ObservableState
    struct State: Equatable {
        /// Full unfiltered collection of loaded salons.
        var salons: IdentifiedArrayOf<Salon> = []
        var isLoading = false
        /// Current text entered in the search field.
        var searchText = ""
        /// Active status filter chips; empty means "all".
        var statusFilter: Set<SalonStatus> = []
        var sortOption: SalonSortOption = .name
        var sortAscending: Bool = true
        /// When `true`, the map view is shown instead of the list.
        var showMap = false
        var showFilterPopover = false
        /// Controls visibility of the status legend sheet.
        var showStatusInfo = false
        /// Active language filter; empty means all languages.
        var languageFilter: Set<String> = []
        /// Active date-range filter IDs; empty means no date constraint.
        var dateRangeFilter: Set<DateRangeOption.ID> = []
        var path: StackState<Path.State> = StackState()
        @Presents var destination: Destination.State?
        var errorMessage: String?

        // MARK: Computed

        /// Salons after applying all active filters and the current sort order.
        var displayedSalons: IdentifiedArrayOf<Salon> {
            IdentifiedArrayOf(uniqueElements: filteredAndSorted(includeStatus: true))
        }

        /// Aggregate counts used by the stats row, computed from the non-status-filtered subset.
        var statCounts: StatCounts {
            let base = filteredAndSorted(includeStatus: false)
            return StatCounts(
                total: base.count,
                new: base.filter { $0.statusEnum == .new }.count,
                contacted: base.filter { $0.statusEnum == .contacted }.count,
                ordered: base.filter { $0.statusEnum == .ordered }.count,
                testDrive: salons.filter { $0.statusEnum == .testDrive }.count
            )
        }

        /// Unique non-empty languages found across all loaded salons, sorted alphabetically.
        var availableLanguages: [LanguageOption] {
            let langs = Set(salons.compactMap(\.language).filter { !$0.isEmpty })
            return langs.sorted().map { LanguageOption(id: $0) }
        }

        /// `true` when at least one language or date-range filter is active.
        var hasAnyFilter: Bool {
            !languageFilter.isEmpty || !dateRangeFilter.isEmpty
        }

        /// Applies all active filters and returns salons in the current sort order.
        /// - Parameter includeStatus: When `false`, the status chip filter is skipped (used for stat counts).
        /// - Returns: Filtered and sorted array of salons.
        private func filteredAndSorted(includeStatus: Bool) -> [Salon] {
            var result = Array(salons)

            if includeStatus, !statusFilter.isEmpty {
                result = result.filter { statusFilter.contains($0.statusEnum) }
            }

            if !searchText.isEmpty {
                let q = searchText.lowercased()
                result = result.filter {
                    $0.name.lowercased().contains(q) ||
                    ($0.address?.lowercased().contains(q) ?? false)
                }
            }

            if !languageFilter.isEmpty {
                result = result.filter { salon in
                    guard let lang = salon.language else { return false }
                    return languageFilter.contains(lang)
                }
            }

            if !dateRangeFilter.isEmpty {
                let activeRanges = DateRangeOption.allCases.filter { dateRangeFilter.contains($0.id) }
                result = result.filter { salon in
                    guard let date = salon.createdAt else { return false }
                    return activeRanges.contains { $0.includes(date) }
                }
            }

            return result.sorted { a, b in
                let asc: Bool
                switch sortOption {
                case .name:
                    asc = a.name.localizedCompare(b.name) == .orderedAscending
                case .leadTemp:
                    let oA = leadTempOrder(a.leadTempEnum), oB = leadTempOrder(b.leadTempEnum)
                    asc = oA != oB ? oA < oB : a.name.localizedCompare(b.name) == .orderedAscending
                case .status:
                    let oA = statusOrder(a.statusEnum), oB = statusOrder(b.statusEnum)
                    asc = oA != oB ? oA < oB : a.name.localizedCompare(b.name) == .orderedAscending
                case .dateAdded:
                    let dA = a.createdAt ?? .distantPast, dB = b.createdAt ?? .distantPast
                    asc = dA < dB
                }
                return sortAscending ? asc : !asc
            }
        }

        /// Numeric sort priority for lead temperature (A < B < C < nil).
        private func leadTempOrder(_ temp: LeadTemp?) -> Int {
            switch temp { case .A: return 0; case .B: return 1; case .C: return 2; case nil: return 3 }
        }

        /// Numeric sort priority for salon status in the default pipeline order.
        private func statusOrder(_ status: SalonStatus) -> Int {
            switch status {
            case .new: return 0; case .contacted: return 1; case .testDrive: return 2
            case .demoScheduled: return 3; case .ordered: return 4; case .other: return 5
            }
        }

        /// Aggregated salon counts displayed in the stats row.
        struct StatCounts: Equatable {
            var total: Int
            var new: Int
            var contacted: Int
            var ordered: Int
            /// Number of salons currently in the test-drive status (always from the full list).
            var testDrive: Int
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case salonsLoaded([Salon])
        case openAdd
        case salonTapped(Salon)
        case salonSaved(Salon)
        case salonDeleted(String)
        case failed(String)
        case clearFilters
        case path(StackActionOf<Path>)
        case destination(PresentationAction<Destination.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {

            case .onLoad:
                guard state.salons.isEmpty else { return .none }
                state.isLoading = true
                state.errorMessage = nil
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        async let salons = firebase.fetchAllSalons()
                        async let _ = firebase.loadWorksOnTags()
                        await send(.salonsLoaded(try await salons))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .salonsLoaded(salons):
                state.isLoading = false
                state.salons = IdentifiedArrayOf(uniqueElements: salons)
                return .none

            case .openAdd:
                guard auth.canEditSalon() else { return .none }
                state.destination = .form(SalonFormFeature.State())
                return .none

            case let .salonTapped(salon):
                state.path.append(.salonDetail(SalonDetailFeature.State(salon: salon)))
                return .none

            case let .salonSaved(salon):
                if state.salons[id: salon.id] != nil {
                    state.salons[id: salon.id] = salon
                } else {
                    state.salons.append(salon)
                }
                state.destination = nil
                // Propagate update into any open salonDetail path element
                for id in state.path.ids {
                    if case var .salonDetail(detail) = state.path[id: id],
                       detail.salon.salonId == salon.salonId {
                        detail.salon = salon
                        state.path[id: id] = .salonDetail(detail)
                    }
                }
                return .none

            case let .salonDeleted(salonId):
                state.salons.removeAll { $0.salonId == salonId }
                // Pop the detail from path if it's open
                if let last = state.path.last,
                   case let .salonDetail(detail) = last,
                   detail.salon.salonId == salonId {
                    state.path.removeLast()
                }
                return .none

            case let .failed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none

            case .clearFilters:
                state.languageFilter = []
                state.dateRangeFilter = []
                return .none

            // MARK: Path propagation
            case let .path(.element(id: _, action: .testDrive(.salonTapped(salon)))):
                state.path.append(.salonDetail(SalonDetailFeature.State(salon: salon)))
                return .none

            case let .path(.element(id: _, action: .salonDetail(.salonUpdated(salon)))):
                return .send(.salonSaved(salon))

            case .path(.element(id: _, action: .salonDetail(.statusAdded(_)))):
                if let last = state.path.last, case let .salonDetail(detail) = last {
                    return .send(.salonSaved(detail.salon))
                }
                return .none

            case .path(.element(id: _, action: .salonDetail(.deleteFinished))):
                // The detail reducer already dismissed itself via @Dependency(\.dismiss).
                // Remove the salon from the list.
                if let last = state.path.last,
                   case let .salonDetail(detail) = last {
                    return .send(.salonDeleted(detail.salon.salonId))
                }
                return .none

            case .path:
                return .none

            // MARK: Destination form
            case let .destination(.presented(.form(.saveSucceeded(salon)))):
                return .send(.salonSaved(salon))

            case .destination:
                return .none

            case .binding:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
    }
}

extension SalonsFeature.Path.State: Equatable {}
extension SalonsFeature.Destination.State: Equatable {}
