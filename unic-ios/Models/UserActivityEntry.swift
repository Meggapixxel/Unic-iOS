import Foundation

struct UserActivityEntry: Identifiable {
    let id: String
    let salonId: String
    let salonName: String
    let status: SalonStatus
    let note: String?
    let timestamp: Date
}
