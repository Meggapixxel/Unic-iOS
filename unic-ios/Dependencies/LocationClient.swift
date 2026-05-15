import ComposableArchitecture
import CoreLocation
import Foundation

@DependencyClient
struct LocationClient: @unchecked Sendable {
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
    nonisolated var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
