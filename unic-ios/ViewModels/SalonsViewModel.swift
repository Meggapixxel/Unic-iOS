//
//  SalonsViewModel.swift
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
        case .name: return String(localized: "sort_by_name")
        case .leadTemp: return String(localized: "sort_by_lead_temp")
        case .status: return String(localized: "sort_by_status")
        }
    }
}

@MainActor
final class SalonsViewModel: ObservableObject {
    @Published var salons: IdentifiedArrayOf<Salon> = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var statusOptions = Options<SalonStatus>(all: IdentifiedArrayOf(uniqueElements: SalonStatus.allCases), selected: [])
    @Published var categoryOptions = Options<Category>()
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

    var displayedSalons: IdentifiedArrayOf<Salon> {
        var result = salons

        // Filter by status
        if statusOptions.hasSelection {
            result = result.filter { statusOptions.selected.contains($0.statusEnum.id) }
        }

        // Filter by category
        if categoryOptions.hasSelection {
            result = result.filter { salon in
                guard let category = salon.categoryName else { return false }
                return categoryOptions.selected.contains(category)
            }
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
        case .demoScheduled: return 2
        case .testing: return 3
        case .ordered: return 4
        case .lost: return 5
        }
    }

    // MARK: - Stats (filtered by search & type, but NOT by status)

    private var salonsForStats: [Salon] {
        var result = Array(salons)

        if categoryOptions.hasSelection {
            result = result.filter { salon in
                guard let category = salon.categoryName else { return false }
                return categoryOptions.selected.contains(category)
            }
        }

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

    // MARK: - Actions

    func loadSalonsIfNeeded() async {
        guard salons.isEmpty else { return }
        await loadSalons()
    }

    func loadSalons() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedSalons = try await service.fetchAllSalons()
            salons = IdentifiedArrayOf(uniqueElements: fetchedSalons)
            buildCategoryOptions()
            buildTypeOptions()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func buildCategoryOptions() {
        let categories = Set(salons.compactMap(\.categoryName))
            .sorted()
            .map { Category(id: $0) }
        categoryOptions.setAll(IdentifiedArrayOf(uniqueElements: categories))
    }

    private func buildTypeOptions() {
        let ignoredTypes: Set<String> = ["establishment", "point_of_interest", "health", "store"]
        let types = Set(salons.compactMap(\.googlePlacesTypes).flatMap { $0 })
        let businessTypes = types.subtracting(ignoredTypes)
            .sorted()
            .map { BusinessType(id: $0) }
        typeOptions.setAll(IdentifiedArrayOf(uniqueElements: businessTypes))
    }

    func retry() {
        Task {
            await loadSalons()
        }
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
