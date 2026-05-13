//
//  TestDriveScreen+ViewModel.swift
//  unic-ios
//

import SwiftUI
import Combine

// MARK: - ViewModel

/// Filters the already-loaded salon list to `testDrive` status entries and schedules
/// local push notifications as reminders. No additional API calls are made — data comes
/// from the `salons` array passed by the parent view.
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

        // Admins see all test drives; managers and sales reps see only entries they created.
        let currentUserId = auth.currentUser?.id
        entries = all.filter { auth.canViewAllTestDrives || $0.createdBy == currentUserId }
    }
}
