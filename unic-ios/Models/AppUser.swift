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

struct UserPlanProgress: Codable, Equatable, Hashable {
    var visitedSalonIds: [String]
    var testDriveCount: Int

    var salonsVisited: Int { visitedSalonIds.count }

    static let empty = UserPlanProgress(visitedSalonIds: [], testDriveCount: 0)
}

struct AppUser: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let role: UserRole
    var planProgress: UserPlanProgress?

    var fullName: String { "\(firstName) \(lastName)" }
    var isAdmin: Bool   { role == .admin }
    var isManager: Bool { role == .manager }
    var isSales: Bool   { role == .sales }
}
