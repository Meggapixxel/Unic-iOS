import Foundation
@preconcurrency import FirebaseFirestore

struct Plan: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var title: String?
    var description: String?
    let startDate: Date
    let endDate: Date
    let createdBy: String
    var targetSalons: Int?
    var targetTestDrives: Int?

    init(
        id: String? = nil,
        title: String? = nil,
        description: String? = nil,
        startDate: Date,
        endDate: Date,
        createdBy: String,
        targetSalons: Int? = nil,
        targetTestDrives: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.createdBy = createdBy
        self.targetSalons = targetSalons
        self.targetTestDrives = targetTestDrives
    }

    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    var isPast: Bool { Date() > endDate }
}
