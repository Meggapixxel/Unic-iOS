import ComposableArchitecture
import CoreLocation
import Foundation

/// TCA dependency that wraps `LocationManager`, providing a single-shot current-location fetch
/// in a testable, injectable interface.
@DependencyClient
struct LocationClient: @unchecked Sendable {
    /// Requests the device's current GPS location once.
    /// - Returns: A `Location` with latitude and longitude, or `nil` when permission is denied
    ///   or the hardware returns no fix.
    var fetchLocation: @Sendable () async -> Location?
}

extension LocationClient: DependencyKey {
    static var liveValue: Self {
        Self(fetchLocation: {
            guard let coord = await LocationManager.shared.fetchCurrentLocation() else { return nil }
            return Location(lat: coord.latitude, lng: coord.longitude)
        })
    }
}

extension DependencyValues {
    /// The registered `LocationClient` dependency, used by TCA reducers to capture check-in coordinates.
    nonisolated var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
