import Foundation

/// Role assigned to a user, controlling feature access throughout the app.
enum UserRole: String, Codable {
    case admin   = "ADMIN"
    case manager = "MANAGER"
    case sales   = "SALES"

    /// Localised label suitable for display in the UI.
    var displayName: String {
        switch self {
        case .admin:   return String.role_admin
        case .manager: return String.role_manager
        case .sales:   return String.role_sales
        }
    }
}

/// Final result counters recorded when a plan period closes.
struct PlanResult: Codable, Equatable, Hashable {
    /// Total number of salon visits completed during the plan period.
    var salons: Int
    /// Total number of test drives completed during the plan period.
    var testDrives: Int
    /// Timestamp at which the result was recorded.
    var createdAt: Date
}

/// An archived plan period stored in the user's `planHistory` subcollection.
struct UserPlanHistoryEntry: Codable, Equatable, Hashable, Identifiable {
    /// Firestore document ID.
    var id: String?
    var startDate: Date
    var endDate: Date
    /// Optional total-period salon target; `nil` means only the daily target applies.
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    /// Optional total-period test-drive target; `nil` means only the daily target applies.
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int
    /// Actual counters achieved by the end of the period.
    var result: PlanResult
}

/// Snapshot of the active plan stored inline in the user document, with embedded progress counters.
struct UserActivePlan: Codable, Equatable, Hashable {
    /// Firestore document ID, mirroring the corresponding `Plan` document.
    var id: String?
    var startDate: Date
    var endDate: Date
    /// Optional total-period salon target.
    var targetSalons: Int?
    var targetSalonsPerDay: Int
    /// Optional total-period test-drive target.
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int

    /// `true` while the current date falls within `[startDate, endDate]`.
    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    /// `true` once the plan period has ended.
    var isPast: Bool   { Date() > endDate }
    /// Calendar days spanned by the plan period (minimum 1).
    var daysTotal: Int { max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) }
    /// Calendar days remaining until `endDate` (minimum 0).
    var daysRemaining: Int { max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0) }
}

/// Authenticated user profile loaded from Firestore and held in memory for the session.
struct AppUser: Codable, Equatable, Hashable, Identifiable {
    /// Firestore UID, matches Firebase Auth UID.
    let id: String
    let firstName: String
    let lastName: String
    /// Role that determines which features and permissions the user has.
    let role: UserRole
    /// The user's currently active plan, if one has been assigned.
    var activePlan: UserActivePlan?

    /// Concatenation of `firstName` and `lastName`.
    var fullName: String { "\(firstName) \(lastName)" }
    var isAdmin: Bool   { role == .admin }
    var isManager: Bool { role == .manager }
    var isSales: Bool   { role == .sales }
}
