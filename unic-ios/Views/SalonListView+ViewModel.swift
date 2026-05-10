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
    case name      = "name"
    case leadTemp  = "leadTemp"
    case status    = "status"
    case dateAdded = "dateAdded"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name:      return String.sort_by_name
        case .leadTemp:  return String.sort_by_lead_temp
        case .status:    return String.sort_by_status
        case .dateAdded: return String.sort_by_date
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
    @Published var languageOptions = Options<LanguageOption>()
    @Published var dateRangeOptions = Options<DateRangeOption>(
        all: IdentifiedArrayOf(uniqueElements: DateRangeOption.allCases), selected: []
    )
    @Published var showMap = false
    @Published var showFilterPopover = false
    @Published var showStatusInfo = false
    @Published var errorMessage: String?
    @Published private(set) var salonFormVM: SalonFormViewModel?

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    var hasAnyFilter: Bool {
        languageOptions.hasSelection || dateRangeOptions.hasSelection
    }

    /// Full filter + sort pipeline applied in-memory.
    var displayedSalons: IdentifiedArrayOf<Salon> {
        IdentifiedArrayOf(uniqueElements: applyFiltersAndSort(salons, includeStatus: true))
    }

    private func applyFiltersAndSort(_ input: some Collection<Salon>, includeStatus: Bool) -> [Salon] {
        var result: [Salon] = Array(input)

        if includeStatus, statusOptions.hasSelection {
            result = result.filter { statusOptions.selected.contains($0.statusEnum.id) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.address?.lowercased().contains(query) ?? false)
            }
        }

        if languageOptions.hasSelection {
            result = result.filter { salon in
                guard let lang = salon.language else { return false }
                return languageOptions.selected.contains(lang)
            }
        }

        if dateRangeOptions.hasSelection {
            result = result.filter { salon in
                guard let date = salon.createdAt else { return false }
                return dateRangeOptions.selectedItems.contains { $0.includes(date) }
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
    // Intentionally omits the status filter so the header always shows counts across all statuses.
    private var salonsForStats: [Salon] {
        applyFiltersAndSort(salons, includeStatus: false)
    }

    var totalCount: Int { salonsForStats.count }
    var newCount: Int { salonsForStats.filter { $0.statusEnum == .new }.count }
    var contactedCount: Int { salonsForStats.filter { $0.statusEnum == .contacted }.count }
    var orderedCount: Int { salonsForStats.filter { $0.statusEnum == .ordered }.count }
    var testDriveCount: Int { salons.filter { $0.statusEnum == .testDrive }.count }

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
            buildLanguageOptions()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func buildLanguageOptions() {
        let langs = Set(salons.compactMap(\.language).filter { !$0.isEmpty })
        let options = langs.sorted().map { LanguageOption(id: $0) }
        languageOptions.setAll(IdentifiedArrayOf(uniqueElements: options))
    }

    func retry() {
        let task = Task { await loadSalons() }
        tasks.append(task)
    }

    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: - Salon Form Lifecycle

    func openAddSalon() {
        salonFormVM = SalonFormViewModel(
            onSaved: { [weak self] salon in
                guard let self else { return }
                self.addSalon(salon)
            },
            onDismiss: { [weak self] in self?.closeAddSalon() }
        )
    }

    func closeAddSalon() {
        salonFormVM = nil
    }

    func addSalon(_ salon: Salon) {
        salons.append(salon)
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
