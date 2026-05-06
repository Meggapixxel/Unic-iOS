//
//  SalonListView+ViewModel.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import SwiftUI
import Combine
import IdentifiedCollections

enum SalonSortOption: String, CaseIterable, Identifiable {
    case name = "name"
    case leadTemp = "leadTemp"
    case status = "status"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return String.sort_by_name
        case .leadTemp: return String.sort_by_lead_temp
        case .status: return String.sort_by_status
        }
    }
}

/// Drives the CRM salon list. All filtering, sorting and stats are computed in-memory
/// from the full `salons` array fetched once at startup.
@MainActor
final class SalonsViewModel: ObservableObject {
    @Published var salons: IdentifiedArrayOf<Salon> = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var statusOptions = Options<SalonStatus>(all: IdentifiedArrayOf(uniqueElements: SalonStatus.allCases), selected: [])
    @Published var sortOption: SalonSortOption = .name
    @Published var sortAscending: Bool = true
    @Published var typeOptions = Options<BusinessType>()
    @Published var showMap = false
    @Published var showSortPopover = false
    @Published var showFilterPopover = false
    @Published var showStatusInfo = false
    @Published var errorMessage: String?

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    /// Full filter + sort pipeline applied in-memory. Status, search, and business-type
    /// filters are combined; result is sorted by the selected `sortOption`.
    var displayedSalons: IdentifiedArrayOf<Salon> {
        var result = salons

        // Filter by status
        if statusOptions.hasSelection {
            result = result.filter { statusOptions.selected.contains($0.statusEnum.id) }
        }

        // Filter by search (name or address)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { salon in
                salon.name.lowercased().contains(query) ||
                (salon.address?.lowercased().contains(query) ?? false)
            }
        }

        // Filter by types
        if typeOptions.hasSelection {
            result = result.filter { salon in
                guard let types = salon.googlePlacesTypes else { return false }
                return !typeOptions.selected.isDisjoint(with: types)
            }
        }

        // Sort
        let sorted = result.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .name:
                result = a.name.localizedCompare(b.name) == .orderedAscending
            case .leadTemp:
                let orderA = leadTempOrder(a.leadTempEnum)
                let orderB = leadTempOrder(b.leadTempEnum)
                if orderA != orderB {
                    result = orderA < orderB
                } else {
                    result = a.name.localizedCompare(b.name) == .orderedAscending
                }
            case .status:
                let orderA = statusOrder(a.statusEnum)
                let orderB = statusOrder(b.statusEnum)
                if orderA != orderB {
                    result = orderA < orderB
                } else {
                    result = a.name.localizedCompare(b.name) == .orderedAscending
                }
            }
            return sortAscending ? result : !result
        }

        return IdentifiedArrayOf(uniqueElements: sorted)
    }

    private func leadTempOrder(_ temp: LeadTemp?) -> Int {
        switch temp {
        case .A: return 0
        case .B: return 1
        case .C: return 2
        case nil: return 3
        }
    }

    private func statusOrder(_ status: SalonStatus) -> Int {
        switch status {
        case .new: return 0
        case .contacted: return 1
        case .testDrive: return 2
        case .demoScheduled: return 3
        case .ordered: return 4
        case .other: return 5
        }
    }

    // MARK: - Stats
    // Intentionally omits the status filter so the header always shows counts across all statuses,
    // even when the list is filtered to a specific status.
    private var salonsForStats: [Salon] {
        var result = Array(salons)

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.address?.lowercased().contains(query) ?? false)
            }
        }

        if typeOptions.hasSelection {
            result = result.filter { salon in
                guard let types = salon.googlePlacesTypes else { return false }
                return !typeOptions.selected.isDisjoint(with: types)
            }
        }

        return result
    }

    var totalCount: Int { salonsForStats.count }
    var newCount: Int { salonsForStats.filter { $0.statusEnum == .new }.count }
    var contactedCount: Int { salonsForStats.filter { $0.statusEnum == .contacted }.count }
    var orderedCount: Int { salonsForStats.filter { $0.statusEnum == .ordered }.count }
    var testDriveCount: Int { Array(salons).filter { $0.statusEnum == .testDrive }.count }

    // MARK: - Actions

    func loadSalonsIfNeeded() async {
        guard salons.isEmpty else { return }
        await loadSalons()
    }

    func loadSalons() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch salons and works-on tags in parallel.
            async let fetchedSalons = service.fetchAllSalons()
            async let _ = service.loadWorksOnTags()
            salons = IdentifiedArrayOf(uniqueElements: try await fetchedSalons)
            buildTypeOptions()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Derives available business-type filter options from Google Places data on each salon.
    /// Generic types (establishment, point_of_interest, etc.) are excluded to keep the filter meaningful.
    private func buildTypeOptions() {
        let ignoredTypes: Set<String> = ["establishment", "point_of_interest", "health", "store"]
        let types = Set(salons.compactMap(\.googlePlacesTypes).flatMap { $0 })
        let businessTypes = types.subtracting(ignoredTypes)
            .sorted()
            .map { BusinessType(id: $0) }
        typeOptions.setAll(IdentifiedArrayOf(uniqueElements: businessTypes))
    }

    func retry() {
        let task = Task { await loadSalons() }
        tasks.append(task)
    }

    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func addSalon(_ salon: Salon) {
        salons.append(salon)
        buildTypeOptions()
    }

    func updateSalon(_ updatedSalon: Salon) {
        salons[id: updatedSalon.id] = updatedSalon
    }

    func deleteSalon(_ salon: Salon) {
        salons.remove(id: salon.id)
    }

    // MARK: - Error Handling

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
