import Foundation
@preconcurrency import FirebaseFirestore

struct DefaultPlan: Codable, Equatable {
    var createdBy: String
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int
}

struct Plan: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let startDate: Date
    let endDate: Date
    let createdBy: String
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int

    init(
        id: String? = nil,
        startDate: Date,
        endDate: Date,
        createdBy: String,
        targetSalons: Int? = nil,
        targetSalonsPerDay: Int = 0,
        targetTestDrives: Int? = nil,
        targetTestDrivesPerDay: Int = 0
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.createdBy = createdBy
        self.targetSalons = targetSalons
        self.targetSalonsPerDay = targetSalonsPerDay
        self.targetTestDrives = targetTestDrives
        self.targetTestDrivesPerDay = targetTestDrivesPerDay
    }

    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    var isPast: Bool { Date() > endDate }
    var daysTotal: Int { max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) }
    var daysRemaining: Int { max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0) }
}
