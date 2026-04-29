import Foundation

struct AppUser: Codable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let role: String

    var fullName: String { "\(firstName) \(lastName)" }
    var isAdmin: Bool { role == "ADMIN" }
}
