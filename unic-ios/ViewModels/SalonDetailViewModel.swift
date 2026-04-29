//
//  SalonDetailViewModel.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import Combine
import IdentifiedCollections

@MainActor
class SalonDetailViewModel: ObservableObject {
    @Published var salon: Salon
    @Published var selectedLeadTemp: LeadTemp?
    @Published var selectedSalonCategory: SalonCategory?
    @Published var selectedLanguage: String = ""
    @Published var selectedWorksOn: [String] = []
    @Published var isSaving = false
    @Published var showLeadTempInfo = false

    // Status History
    @Published var statusHistory: IdentifiedArrayOf<StatusHistoryEntry> = []
    @Published var isLoadingHistory = false
    @Published var showAddStatus = false
    @Published var showStatusHistory = false

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    // Delete
    @Published var showDeleteConfirmation = false

    private let service = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()

    var onSalonUpdated: (Salon) -> Void
    var onSalonDeleted: () -> Void

    var currentStatus: SalonStatus {
        salon.statusEnum
    }

    init(salon: Salon, onSalonUpdated: @escaping (Salon) -> Void, onSalonDeleted: @escaping () -> Void) {
        self.salon = salon
        self.selectedLeadTemp = salon.leadTempEnum
        self.selectedSalonCategory = salon.salonCategoryEnum
        self.selectedLanguage = salon.language ?? "cs"
        self.selectedWorksOn = salon.worksOn ?? []
        self.onSalonUpdated = onSalonUpdated
        self.onSalonDeleted = onSalonDeleted

        setupBindings()
    }

    private func setupBindings() {
        $selectedLeadTemp
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newLeadTemp in
                self?.handleLeadTempChange(newLeadTemp)
            }
            .store(in: &cancellables)

        $selectedSalonCategory
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newCategory in
                self?.handleSalonCategoryChange(newCategory)
            }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.handleLanguageChange()
            }
            .store(in: &cancellables)

        $selectedWorksOn
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newTags in
                self?.handleWorksOnChange(newTags)
            }
            .store(in: &cancellables)
    }

    // MARK: - Status History

    func loadStatusHistory() {
        Task {
            isLoadingHistory = true
            defer { isLoadingHistory = false }

            do {
                let history = try await service.fetchStatusHistory(salonId: salon.salonId)
                statusHistory = IdentifiedArrayOf(uniqueElements: history)
            } catch {
                showError(String(localized: "error"), message: String(localized: "history_load_error"))
            }
        }
    }

    func addStatusEntry(status: SalonStatus, note: String?) {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await service.addStatusHistoryEntry(
                    salonId: salon.salonId,
                    status: status,
                    note: note?.isEmpty == true ? nil : note
                )

                // Reload history and update local salon status
                let history = try await service.fetchStatusHistory(salonId: salon.salonId)
                statusHistory = IdentifiedArrayOf(uniqueElements: history)

                // Update local salon object
                if let updatedSalon = try await service.getSalon(id: salon.salonId) {
                    salon = updatedSalon
                    onSalonUpdated(updatedSalon)
                }

                showAddStatus = false
            } catch {
                showError(String(localized: "error"), message: error.localizedDescription)
            }
        }
    }

    func deleteStatusEntry(_ entry: StatusHistoryEntry) {
        guard let entryId = entry.id else { return }

        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await service.deleteStatusHistoryEntry(salonId: salon.salonId, entryId: entryId)
                statusHistory.remove(id: entryId)
            } catch {
                showError(String(localized: "error"), message: error.localizedDescription)
            }
        }
    }

    // MARK: - Handlers

    private func handleLeadTempChange(_ leadTemp: LeadTemp?) {
        Task {
            await updateLeadTemp(leadTemp)
        }
    }

    private func handleSalonCategoryChange(_ category: SalonCategory?) {
        Task {
            await updateSalonCategory(category)
        }
    }

    // MARK: - Update Methods

    private func updateLeadTemp(_ leadTemp: LeadTemp?) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.updateSalonLeadTemp(salonId: salon.salonId, leadTemp: leadTemp)
        } catch {
            showError(String(localized: "save_error"), message: error.localizedDescription)
            selectedLeadTemp = salon.leadTempEnum
        }
    }

    private func updateSalonCategory(_ category: SalonCategory?) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.updateSalonCategory(salonId: salon.salonId, category: category)
        } catch {
            showError(String(localized: "save_error"), message: error.localizedDescription)
            selectedSalonCategory = salon.salonCategoryEnum
        }
    }

    private func handleLanguageChange() {
        Task {
            await saveLanguage()
        }
    }

    private func saveLanguage() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.updateSalonLanguage(salonId: salon.salonId, language: selectedLanguage)
        } catch {
            showError(String(localized: "save_error"), message: error.localizedDescription)
            selectedLanguage = salon.language ?? "cs"
        }
    }

    private func handleWorksOnChange(_ tags: [String]) {
        Task { await updateWorksOn(tags) }
    }

    private func updateWorksOn(_ tags: [String]) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updateSalonWorksOn(salonId: salon.salonId, worksOn: tags)
        } catch {
            showError(String(localized: "save_error"), message: error.localizedDescription)
            selectedWorksOn = salon.worksOn ?? []
        }
    }

    // MARK: - Error Handling

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: - Delete

    func deleteSalon() {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await service.deleteSalon(salonId: salon.salonId)
                onSalonDeleted()
            } catch {
                showError(String(localized: "error"), message: error.localizedDescription)
            }
        }
    }

    // MARK: - Computed Properties

    var hasLocation: Bool {
        salon.maps?.location != nil
    }
}
