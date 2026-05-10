//
//  SalonDetailView+ViewModel.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import Combine
import IdentifiedCollections

/// Manages a single CRM salon record. Status history is the primary CRM action here —
/// each status change creates a Firestore subcollection entry and updates the denormalized
/// `latestStatusEntry` field on the salon document for list-level display without extra fetches.
///
/// Changes propagate back to the list via `onSalonUpdated` / `onSalonDeleted` callbacks.
@MainActor
class SalonDetailViewModel: ObservableObject {
    @Published var salon: Salon
    @Published var isSaving = false
    @Published var showLeadTempInfo = false
    @Published var showStatusInfo = false

    // Status History
    @Published var statusHistory: IdentifiedArrayOf<StatusHistoryEntry> = []
    /// Mirrors the denormalized `salon.latestStatusEntry` — updated locally after mutations
    /// to avoid a full re-fetch of the salon document.
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
    @Published private(set) var salonFormVM: SalonFormViewModel?

    private let service = FirebaseService.shared

    /// All active tasks — cancelled together when the view disappears via `cancelAllTasks()`.
    private var tasks: [Task<Void, Never>] = []

    /// Called after any mutation so the parent list view stays in sync without a full reload.
    var onSalonUpdated: (Salon) -> Void
    var onSalonDeleted: () -> Void

    var currentStatus: SalonStatus { salon.statusEnum }

    init(salon: Salon, onSalonUpdated: @escaping (Salon) -> Void, onSalonDeleted: @escaping () -> Void) {
        self.salon = salon
        self.onSalonUpdated = onSalonUpdated
        self.onSalonDeleted = onSalonDeleted
    }

    /// Cancels all in-flight tasks. Call from `.onDisappear` in the owning view.
    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: - Edit Form Lifecycle

    func openEditSalon() {
        salonFormVM = SalonFormViewModel(
            existingSalon: salon,
            onSaved: { [weak self] updated in
                guard let self else { return }
                self.salon = updated
                self.onSalonUpdated(updated)
            },
            onDismiss: { [weak self] in self?.closeEditSalon() }
        )
    }

    func closeEditSalon() {
        salonFormVM = nil
    }

    // MARK: - Status History

    func loadLatestStatusEntry() {
        let task = Task {
            do {
                latestStatusEntry = try await service.fetchLatestStatusEntry(salonId: salon.salonId)
            } catch {
                showError(String.error, message: error.localizedDescription)
            }
        }
        tasks.append(task)
    }

    func loadStatusHistory() {
        let task = Task {
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
        tasks.append(task)
    }

    func addStatusEntry(status: SalonStatus, note: String?, createdBy: String?, date: Date? = nil) {
        let task = Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.addStatusHistoryEntry(
                    salonId: salon.salonId,
                    status: status,
                    currentStatus: salon.statusEnum,
                    note: note?.isEmpty == true ? nil : note,
                    createdBy: createdBy,
                    date: date
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
        tasks.append(task)
    }

    func updateStatusEntryNote(_ entry: StatusHistoryEntry, note: String?) {
        guard let entryId = entry.id else { return }
        let task = Task {
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
        tasks.append(task)
    }

    func deleteStatusEntry(_ entry: StatusHistoryEntry) {
        guard let entryId = entry.id else { return }
        let task = Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.deleteStatusHistoryEntry(salonId: salon.salonId, entryId: entryId)
                statusHistory.remove(id: entryId)
            } catch {
                showError(String.error, message: error.localizedDescription)
            }
        }
        tasks.append(task)
    }

    // MARK: - Delete

    func deleteSalon() {
        let task = Task {
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
        tasks.append(task)
    }

    // MARK: - Error

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
