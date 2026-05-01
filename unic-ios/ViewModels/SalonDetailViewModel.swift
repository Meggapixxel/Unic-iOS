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
    @Published var isSaving = false
    @Published var showLeadTempInfo = false
    @Published var showStatusInfo = false

    // Status History
    @Published var statusHistory: IdentifiedArrayOf<StatusHistoryEntry> = []
    @Published var latestStatusEntry: StatusHistoryEntry? = nil
    @Published var isLoadingHistory = false
    @Published var showAddStatus = false
    @Published var showStatusHistory = false

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    // Delete
    @Published var showDeleteConfirmation = false
    @Published var shouldDismiss = false

    // Edit
    @Published var showEditSalon = false

    private let service = FirebaseService.shared

    var onSalonUpdated: (Salon) -> Void
    var onSalonDeleted: () -> Void

    var currentStatus: SalonStatus { salon.statusEnum }

    init(salon: Salon, onSalonUpdated: @escaping (Salon) -> Void, onSalonDeleted: @escaping () -> Void) {
        self.salon = salon
        self.onSalonUpdated = onSalonUpdated
        self.onSalonDeleted = onSalonDeleted
    }

    // MARK: - Status History

    func loadLatestStatusEntry() {
        Task {
            latestStatusEntry = try? await service.fetchLatestStatusEntry(salonId: salon.salonId)
        }
    }

    func loadStatusHistory() {
        Task {
            isLoadingHistory = true
            defer { isLoadingHistory = false }
            do {
                let history = try await service.fetchStatusHistory(salonId: salon.salonId)
                statusHistory = IdentifiedArrayOf(uniqueElements: history)
                latestStatusEntry = statusHistory.first
            } catch {
                showError(String.error, message: String.history_load_error)
            }
        }
    }

    func addStatusEntry(status: SalonStatus, note: String?, createdBy: String?) {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.addStatusHistoryEntry(
                    salonId: salon.salonId,
                    status: status,
                    note: note?.isEmpty == true ? nil : note,
                    createdBy: createdBy
                )
                if let updatedSalon = try await service.getSalon(id: salon.salonId) {
                    salon = updatedSalon
                    latestStatusEntry = updatedSalon.latestStatusEntry
                    onSalonUpdated(updatedSalon)
                }
                let history = try await service.fetchStatusHistory(salonId: salon.salonId)
                statusHistory = IdentifiedArrayOf(uniqueElements: history)
                showAddStatus = false
            } catch {
                showError(String.error, message: error.localizedDescription)
            }
        }
    }

    func updateStatusEntryNote(_ entry: StatusHistoryEntry, note: String?) {
        guard let entryId = entry.id else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.updateStatusEntryNote(
                    salonId: salon.salonId,
                    entryId: entryId,
                    note: note?.isEmpty == true ? nil : note
                )
                let history = try await service.fetchStatusHistory(salonId: salon.salonId)
                statusHistory = IdentifiedArrayOf(uniqueElements: history)
                latestStatusEntry = statusHistory.first
            } catch {
                showError(String.error, message: error.localizedDescription)
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
                showError(String.error, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Delete

    func deleteSalon() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.deleteSalon(salonId: salon.salonId)
                onSalonDeleted()
                shouldDismiss = true
            } catch {
                showError(String.error, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Error

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
