//
//  StatusHistoryEntry.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
@preconcurrency import FirebaseFirestore

struct StatusHistoryEntry: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    let status: String
    let note: String?
    let timestamp: Date
    let createdBy: String?
    let date: Date?

    var statusEnum: SalonStatus {
        SalonStatus(rawValue: status) ?? .new
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    var formattedDate: String {
        Self.timestampFormatter.string(from: timestamp)
    }
}
