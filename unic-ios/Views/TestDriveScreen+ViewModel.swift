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
    /// Active test-drive entries visible to the current user.
    @Published var entries: [TestDriveEntry] = []
    @Published var isLoading = false
    /// Whether push notifications are authorized; shown as a banner if `false`.
    @Published var notificationsAllowed = true

    private let notifications = NotificationService.shared

    /// Filters `salons` to test-drive entries, schedules notifications, and applies role-based visibility.
    /// Admins see all entries; managers and sales reps see only entries they created.
    /// - Parameter salons: The full salon list provided by the parent view.
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
