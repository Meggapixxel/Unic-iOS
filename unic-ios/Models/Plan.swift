import Foundation
@preconcurrency import FirebaseFirestore

/// Template plan values stored at the manager level and used to pre-fill new plan creation forms.
struct DefaultPlan: Codable, Equatable {
    /// UID of the manager who created this default.
    var createdBy: String
    /// Optional total-period salon target.
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    /// Optional total-period test-drive target.
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int
}

/// A work plan assigned to a sales user for a specific date range, stored in Firestore.
struct Plan: Codable, Identifiable, Equatable {
    /// Firestore document ID.
    @DocumentID var id: String?
    let startDate: Date
    let endDate: Date
    /// UID of the manager who created the plan.
    let createdBy: String
    /// Optional total-period salon visit target; `nil` means no cap, only daily target applies.
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    /// Optional total-period test-drive target.
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

    /// `true` while the current date falls within `[startDate, endDate]`.
    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    /// `true` once the plan period has ended.
    var isPast: Bool { Date() > endDate }
    /// Calendar days spanned by the plan period (minimum 1).
    var daysTotal: Int { max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) }
    /// Calendar days remaining until `endDate` (minimum 0).
    var daysRemaining: Int { max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0) }
}
