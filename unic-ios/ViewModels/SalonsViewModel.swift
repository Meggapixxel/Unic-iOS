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

@MainActor
class SalonsViewModel: ObservableObject {
    @Published var salons: IdentifiedArrayOf<Salon> = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedStatus: SalonStatus?
    @Published var errorMessage: String?

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    private let service = FirebaseService.shared

    var displayedSalons: IdentifiedArrayOf<Salon> {
        var result = salons

        if let status = selectedStatus {
            result = result.filter { $0.statusEnum == status }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { salon in
                salon.name.lowercased().contains(query) ||
                (salon.address?.lowercased().contains(query) ?? false) ||
                (salon.instagramHandle?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    // MARK: - Stats

    var totalCount: Int { salons.count }
    var newCount: Int { salons.filter { $0.statusEnum == .new }.count }
    var contactedCount: Int { salons.filter { $0.statusEnum == .contacted }.count }
    var orderedCount: Int { salons.filter { $0.statusEnum == .ordered }.count }

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
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func retry() {
        Task {
            await loadSalons()
        }
    }

    func updateSalon(_ updatedSalon: Salon) {
        salons[id: updatedSalon.id] = updatedSalon
    }

    // MARK: - Error Handling

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
