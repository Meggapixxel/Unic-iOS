//
//  TestDriveView+ViewModel.swift
//  unic-ios
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class TestDriveViewModel: ObservableObject {
    @Published var entries: [TestDriveEntry] = []
    @Published var isLoading = false
    @Published var notificationsAllowed = true

    private let notifications = NotificationService.shared

    func load(from salons: [Salon]) async {
        isLoading = true
        defer { isLoading = false }

        notificationsAllowed = await notifications.isAuthorized()

        let auth = AuthService.shared
        let all: [TestDriveEntry] = salons
            .filter { $0.statusEnum == .testDrive }
            .map { salon in
                let latest = salon.latestStatusEntry
                return TestDriveEntry(
                    id: salon.salonId,
                    salon: salon,
                    date: latest?.timestamp ?? Date(),
                    note: latest?.note,
                    createdBy: latest?.createdBy
                )
            }
            .sorted { $0.date > $1.date }

        if notificationsAllowed {
            await notifications.scheduleTestDriveReminders(for: all)
        }

        let currentUserId = auth.currentUser?.id
        entries = all.filter { auth.canViewAllTestDrives || $0.createdBy == currentUserId }
    }
}
