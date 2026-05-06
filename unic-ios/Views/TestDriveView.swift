//
//  TestDriveView.swift
//  unic-ios
//

import SwiftUI
import Combine

// MARK: - Model

struct TestDriveEntry: Identifiable {
    let id: String           // salonId
    let salon: Salon
    let date: Date
    let note: String?
    let createdBy: String?

    var deadline: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
    }

    var deadlineColor: Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        if days < 0 { return .red }
        if days == 0 { return .red }
        if days == 1 { return .orange }
        return .secondary
    }

    var articleLine: String? {
        guard let note, !note.isEmpty else { return nil }
        // First line of note contains articles (comma-separated)
        let firstLine = note.components(separatedBy: "\n").first ?? note
        return firstLine.isEmpty ? nil : firstLine
    }

    var commentLine: String? {
        let lines = note?.components(separatedBy: "\n") ?? []
        guard lines.count > 1 else { return nil }
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

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

// MARK: - View

struct TestDriveView: View {
    let salons: [Salon]
    let onSalonUpdated: (Salon) -> Void
    let onSalonDeleted: (Salon) -> Void

    @StateObject private var viewModel = TestDriveViewModel()

    var body: some View {
        List {
            if !viewModel.notificationsAllowed {
                Section {
                    NotificationsDisabledBanner()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.orange.opacity(0.08))
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    String.test_drive_empty,
                    systemImage: "flask"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.entries) { entry in
                    NavigationLink {
                        SalonDetailView(
                            salon: entry.salon,
                            onSalonUpdated: { updated in
                                onSalonUpdated(updated)
                                Task { await viewModel.load(from: salons) }
                            },
                            onSalonDeleted: {
                                onSalonDeleted(entry.salon)
                                Task { await viewModel.load(from: salons) }
                            }
                        )
                    } label: {
                        TestDriveRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(String.test_drive)
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load(from: salons) }
    }
}

// MARK: - Notifications Disabled Banner

private struct NotificationsDisabledBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(String.notif_disabled_title)
                    .font(.subheadline.weight(.semibold))
                Text(String.notif_disabled_body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(String.notif_disabled_action) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Row

private struct TestDriveRow: View {
    let entry: TestDriveEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.salon.displayName)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption2)
                    Text(entry.deadline.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
                .foregroundStyle(entry.deadlineColor)
            }

            if let articles = entry.articleLine {
                Text(articles)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if let comment = entry.commentLine {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let city = entry.salon.city {
                Text(city)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
