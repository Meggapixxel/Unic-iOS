import Foundation
@preconcurrency import FirebaseFirestore

struct Plan: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let createdBy: String

    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    var isPast: Bool { Date() > endDate }
}
