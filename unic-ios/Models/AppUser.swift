import Foundation

enum UserRole: String, Codable {
    case admin   = "ADMIN"
    case manager = "MANAGER"
    case sales   = "SALES"

    var displayName: String {
        switch self {
        case .admin:   return String.role_admin
        case .manager: return String.role_manager
        case .sales:   return String.role_sales
        }
    }
}

// Snapshot of active plan stored in user document, with embedded progress counters.
struct UserActivePlan: Codable, Equatable, Hashable {
    var id: String?
    var startDate: Date
    var endDate: Date
    var targetSalons: Int?
    var targetSalonsPerDay: Int?
    var targetTestDrives: Int?
    var targetTestDrivesPerDay: Int?

    var isActive: Bool { Date() >= startDate && Date() <= endDate }
    var isPast: Bool   { Date() > endDate }
    var daysTotal: Int { max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1) }
    var daysRemaining: Int { max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0) }
}

struct AppUser: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let role: UserRole
    var activePlan: UserActivePlan?

    var fullName: String { "\(firstName) \(lastName)" }
    var isAdmin: Bool   { role == .admin }
    var isManager: Bool { role == .manager }
    var isSales: Bool   { role == .sales }
}
