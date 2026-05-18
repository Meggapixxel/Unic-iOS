//
//  TestDriveScreen.swift
//  unic-ios
//

import SwiftUI
import Combine

// MARK: - Model

/// A single active test-drive, combining a salon's latest status-history entry with deadline logic.
struct TestDriveEntry: Identifiable {
    let id: String           // salonId
    let salon: Salon
    /// The timestamp of the latest status-history entry that triggered the test drive.
    let date: Date
    let note: String?
    let createdBy: String?

    /// Computed deadline based on `testDriveStartDate` (or `date`) plus the configured duration.
    @MainActor var deadline: Date {
        let start = salon.testDriveStartDate ?? date
        let days = FirebaseService.shared.testDriveDuration
        return Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
    }

    /// Color coding: red when overdue or due today, orange when one day away, secondary otherwise.
    @MainActor var deadlineColor: Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        if days < 0 { return .red }
        if days == 0 { return .red }
        if days == 1 { return .orange }
        return .secondary
    }

    /// The first line of the note (comma-separated article codes), or `nil` if empty.
    var articleLine: String? {
        guard let note, !note.isEmpty else { return nil }
        // First line of note contains articles (comma-separated)
        let firstLine = note.components(separatedBy: "\n").first ?? note
        return firstLine.nilIfEmpty
    }

    /// Everything after the first line of the note (free-text comment), or `nil` if absent.
    var commentLine: String? {
        let lines = note?.components(separatedBy: "\n") ?? []
        guard lines.count > 1 else { return nil }
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.nilIfEmpty
    }
}

// MARK: - View

/// List screen showing active test drives with deadline badges and an optional notifications-disabled banner.
struct TestDriveScreen: View {
    /// The full salon array from which test-drive entries are derived.
    let salons: [Salon]
    /// Called when the user taps a row, passing the corresponding salon for navigation.
    let onSalonTapped: (Salon) -> Void

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
                    Button { onSalonTapped(entry.salon) } label: {
                        TestDriveRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .navigationInlineTitle(String.test_drive)
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
