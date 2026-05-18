//
//  StatusHistoryEntry.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
@preconcurrency import FirebaseFirestore

/// An immutable record of a single salon-status change, stored in Firestore and used to build the activity timeline.
struct StatusHistoryEntry: Codable, Identifiable, Hashable {
    /// Firestore document ID.
    @DocumentID var id: String?
    /// Raw pipeline status string at the time of the change.
    let status: String
    /// Optional note added by the sales rep during the status update.
    let note: String?
    /// Server-side timestamp of when the status change was recorded.
    let timestamp: Date
    /// UID of the user who performed the update.
    let createdBy: String?
    /// Optional client-selected date (e.g. for scheduling a demo), distinct from `timestamp`.
    let date: Date?
    /// GPS coordinates captured when the status was updated.
    let userLocation: Location?

    /// Typed pipeline status, defaulting to `.new` for unrecognised raw values.
    var statusEnum: SalonStatus {
        SalonStatus(rawValue: status) ?? .new
    }

    /// Shared formatter for the `formattedDate` computed property.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    /// `timestamp` formatted with medium date style and short time style using the current locale.
    var formattedDate: String {
        Self.timestampFormatter.string(from: timestamp)
    }
}
