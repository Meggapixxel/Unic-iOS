//
//  StatusHistoryEntry.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import FirebaseFirestore

struct StatusHistoryEntry: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    let status: String
    let note: String?
    let timestamp: Date

    var statusEnum: SalonStatus {
        SalonStatus(rawValue: status) ?? .new
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: timestamp)
    }
}
