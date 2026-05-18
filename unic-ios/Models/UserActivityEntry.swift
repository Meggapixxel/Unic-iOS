import CoreLocation
import Foundation

/// A flattened, view-ready representation of a single sales-rep activity event,
/// assembled from a `StatusHistoryEntry` and its parent `Salon` for display in the activity feed and map.
struct UserActivityEntry: Identifiable, Equatable {
    /// Firestore document ID of the underlying `StatusHistoryEntry`.
    let id: String
    /// Firestore document ID of the associated salon.
    let salonId: String
    /// Display name of the associated salon at the time the entry was loaded.
    let salonName: String
    /// Typed pipeline status recorded for this activity event.
    let status: SalonStatus
    /// Optional note left by the sales rep.
    let note: String?
    /// Timestamp of the status change.
    let timestamp: Date
    /// GPS latitude captured at the time of the update, if available.
    let latitude: Double?
    /// GPS longitude captured at the time of the update, if available.
    let longitude: Double?

    /// `CLLocationCoordinate2D` for map display, or `nil` when coordinates are absent.
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
