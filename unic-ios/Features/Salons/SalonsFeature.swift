// FILE: unic-ios/Features/Salons/SalonsFeature.swift

import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
struct SalonsFeature {

    // MARK: - Path

    @Reducer
    struct Path {
        @ObservableState
        enum State: Equatable {
            case salonDetail(SalonDetailFeature.State)
            case testDrive(TestDriveFeature.State)
            case routePlanner(RoutePlannerFeature.State)
        }

        enum Action {
            case salonDetail(SalonDetailFeature.Action)
            case testDrive(TestDriveFeature.Action)
            case routePlanner(RoutePlannerFeature.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: \.salonDetail, action: \.salonDetail) { SalonDetailFeature() }
            Scope(state: \.testDrive, action: \.testDrive) { TestDriveFeature() }
            Scope(state: \.routePlanner, action: \.routePlanner) { RoutePlannerFeature() }
        }
    }

    // MARK: - Destination

    @Reducer
    struct Destination {
        @ObservableState
        enum State: Equatable {
            case form(SalonFormFeature.State)
        }

        enum Action {
            case form(SalonFormFeature.Action)
        }

        var body: some ReducerOf<Self> {
            Scope(state: \.form, action: \.form) { SalonFormFeature() }
        }
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var salons: IdentifiedArrayOf<Salon> = []
        var isLoading = false
        var searchText = ""
        var statusFilter: Set<SalonStatus> = []
        var sortOption: SalonSortOption = .name
        var sortAscending: Bool = true
        var showMap = false
        var showFilterPopover = false
        var showStatusInfo = false
        var languageFilter: Set<String> = []
        var dateRangeFilter: Set<DateRangeOption.ID> = []
        var path: StackState<Path.State> = StackState()
        @Presents var destination: Destination.State?
        var errorMessage: String?

        // MARK: Computed

        var displayedSalons: IdentifiedArrayOf<Salon> {
            IdentifiedArrayOf(uniqueElements: filteredAndSorted(includeStatus: true))
        }

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

        var availableLanguages: [LanguageOption] {
            let langs = Set(salons.compactMap(\.language).filter { !$0.isEmpty })
            return langs.sorted().map { LanguageOption(id: $0) }
        }

        var hasAnyFilter: Bool {
            !languageFilter.isEmpty || !dateRangeFilter.isEmpty
        }

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

        private func leadTempOrder(_ temp: LeadTemp?) -> Int {
            switch temp { case .A: return 0; case .B: return 1; case .C: return 2; case nil: return 3 }
        }

        private func statusOrder(_ status: SalonStatus) -> Int {
            switch status {
            case .new: return 0; case .contacted: return 1; case .testDrive: return 2
            case .demoScheduled: return 3; case .ordered: return 4; case .other: return 5
            }
        }

        struct StatCounts: Equatable {
            var total: Int
            var new: Int
            var contacted: Int
            var ordered: Int
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
                return .run { send in
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
                for index in state.path.indices {
                    if case var .salonDetail(detail) = state.path[index],
                       detail.salon.salonId == salon.salonId {
                        detail.salon = salon
                        state.path[index] = .salonDetail(detail)
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
            case let .path(.element(id: _, action: .salonDetail(.salonUpdated(salon)))):
                return .send(.salonSaved(salon))

            case let .path(.element(id: _, action: .salonDetail(.deleteFinished))):
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
        .forEach(\.path, action: \.path) { Path() }
        .ifLet(\.$destination, action: \.destination) { Destination() }
    }
}
