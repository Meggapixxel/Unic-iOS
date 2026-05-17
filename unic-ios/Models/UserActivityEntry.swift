import CoreLocation
import Foundation

struct UserActivityEntry: Identifiable, Equatable {
    let id: String
    let salonId: String
    let salonName: String
    let status: SalonStatus
    let note: String?
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
