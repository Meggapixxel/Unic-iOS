//
//  RoutePlannerScreen+ViewModel.swift
//  unic-ios
//
//  Created by UNIC Team on 31/03/2026.
//

import Foundation
import SwiftUI
import Combine
import MapKit
import CoreLocation
import IdentifiedCollections

/// Two-phase ViewModel for the route planner:
///   Phase 1 (selection): user picks salons from a list/map.
///   Phase 2 (route): stops are ordered via nearest-neighbor heuristic, then
///   routed segment-by-segment with MKDirections.
///
/// Route calculation runs in a stored `currentTask` so it can be cancelled when the user
/// switches transport type, removes a stop, or navigates back.
@MainActor
final class RouteViewModel: ObservableObject {

    // MARK: - Selection Phase

    /// Salons available for selection (those with a valid coordinate).
    @Published var availableSalons: [Salon] = []
    /// Set of `salonId` values the user has selected for inclusion in the route.
    @Published var selectedIds: Set<String> = []
    /// Whether the selection phase is showing the map instead of the list.
    @Published var showSelectionMap = false
    @Published var selectionMapPosition: MapCameraPosition = .automatic

    var isPresented: Binding<Bool>?

    private var userLocation: CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return nil }
        return manager.location?.coordinate
    }

    // MARK: - Route Phase

    /// Ordered list of stops for the active route (after nearest-neighbor optimization).
    @Published var stops: [Salon] = []
    /// Accumulated polyline coordinates from all MKDirections segments.
    @Published var routePolylineCoordinates: [CLLocationCoordinate2D] = []
    /// Total route distance in meters.
    @Published var totalDistance: CLLocationDistance = 0
    /// Estimated total travel time in seconds.
    @Published var totalTime: TimeInterval = 0
    @Published var transportType: MKDirectionsTransportType = .automobile
    /// Whether a directions calculation task is in progress.
    @Published var isCalculating = false
    /// Fraction (0–1) of direction segments that have been calculated.
    @Published var calculationProgress: Double = 0
    /// Whether the route-map phase is currently visible.
    @Published var showRoute = false

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed

    var selectedCount: Int { selectedIds.count }
    /// Whether enough salons are selected to build a route (minimum 2).
    var canBuildRoute: Bool { selectedIds.count >= 2 }

    /// Human-readable distance string using the system locale's preferred unit scale.
    var formattedDistance: String {
        let measurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    /// Human-readable travel time string (hours and minutes, dropping leading zeros).
    var formattedTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: totalTime) ?? "—"
    }

    // MARK: - Init

    init(salons: IdentifiedArrayOf<Salon>, isPresented: Binding<Bool>? = nil) {
        self.availableSalons = salons.filter { $0.coordinate != nil }
        self.isPresented = isPresented

        // Start map at user location or Prague center, ~5km radius
        let center = self.userLocation ?? CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378)
        self.selectionMapPosition = .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        ))
    }

    /// Cancels any in-flight route task and dismisses the planner sheet.
    func dismiss() {
        currentTask?.cancel()
        isPresented?.wrappedValue = false
    }

    // MARK: - Selection

    /// Adds the salon to the selection if not already present, or removes it if it is.
    func toggleSelection(_ salon: Salon) {
        if selectedIds.contains(salon.salonId) {
            selectedIds.remove(salon.salonId)
        } else {
            selectedIds.insert(salon.salonId)
        }
    }

    /// Returns `true` if the salon is currently in the selection.
    func isSelected(_ salon: Salon) -> Bool {
        selectedIds.contains(salon.salonId)
    }

    /// Selects all available salons (those with coordinates).
    func selectAll() {
        selectedIds = Set(availableSalons.map(\.salonId))
    }

    /// Clears the entire selection.
    func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - Build Route

    /// Optimizes stop order and transitions to the route-map phase, then triggers direction calculation.
    func buildRoute() {
        let selected = availableSalons.filter { selectedIds.contains($0.salonId) }
        guard selected.count >= 2 else { return }

        stops = optimizeOrder(selected, startingFrom: userLocation)
        showRoute = true
        calculateDirections()
    }

    // MARK: - Nearest-Neighbor Optimization
    //
    // Greedy heuristic: always move to the closest unvisited salon from the current position.
    // If user location is available it serves as the starting point; otherwise the salon
    // nearest to Prague center is picked first. O(n²) — acceptable for the typical ≤20 stops.

    private func optimizeOrder(_ salons: [Salon], startingFrom userLocation: CLLocationCoordinate2D?) -> [Salon] {
        guard salons.count > 1 else { return salons }

        var remaining = salons
        var ordered: [Salon] = []
        var currentLocation: CLLocationCoordinate2D

        if let userLoc = userLocation {
            currentLocation = userLoc
        } else {
            // Start from salon nearest to Prague center
            let pragueCenter = CLLocation(latitude: 50.0755, longitude: 14.4378)
            remaining.sort { a, b in
                let locA = CLLocation(latitude: a.coordinate!.latitude, longitude: a.coordinate!.longitude)
                let locB = CLLocation(latitude: b.coordinate!.latitude, longitude: b.coordinate!.longitude)
                return locA.distance(from: pragueCenter) < locB.distance(from: pragueCenter)
            }
            let first = remaining.removeFirst()
            ordered.append(first)
            currentLocation = first.coordinate!
        }

        while !remaining.isEmpty {
            let currentCL = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)

            let nearestIndex = remaining.enumerated().min(by: { a, b in
                let locA = CLLocation(latitude: a.element.coordinate!.latitude, longitude: a.element.coordinate!.longitude)
                let locB = CLLocation(latitude: b.element.coordinate!.latitude, longitude: b.element.coordinate!.longitude)
                return locA.distance(from: currentCL) < locB.distance(from: currentCL)
            })!.offset

            let nearest = remaining.remove(at: nearestIndex)
            ordered.append(nearest)
            currentLocation = nearest.coordinate!
        }

        return ordered
    }

    // MARK: - MKDirections Calculation
    //
    // Fetches real road routes for every consecutive stop pair, accumulating polyline
    // coordinates, distance, and expected travel time. Results are published after each
    // segment so the map updates progressively rather than waiting for all pairs.
    //
    // On MKDirections failure (e.g., no route found, network offline) the segment falls
    // back to a straight line with an estimated travel time based on transport speed.

    private func calculateDirections() {
        currentTask?.cancel()

        currentTask = Task {
            isCalculating = true
            calculationProgress = 0
            routePolylineCoordinates = []
            totalDistance = 0
            totalTime = 0

            let pairs = stops.count - 1
            guard pairs > 0 else {
                isCalculating = false
                return
            }

            var allCoordinates: [CLLocationCoordinate2D] = []
            var accDistance: CLLocationDistance = 0
            var accTime: TimeInterval = 0

            for i in 0..<pairs {
                guard !Task.isCancelled else { return }

                guard let originCoord = stops[i].coordinate,
                      let destCoord = stops[i + 1].coordinate else { continue }

                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
                request.transportType = transportType
                request.requestsAlternateRoutes = false

                do {
                    let directions = MKDirections(request: request)
                    let response = try await directions.calculate()

                    if let route = response.routes.first {
                        let points = route.polyline.points()
                        let pointCount = route.polyline.pointCount
                        for j in 0..<pointCount {
                            allCoordinates.append(points[j].coordinate)
                        }

                        accDistance += route.distance
                        accTime += route.expectedTravelTime
                    }
                } catch {
                    // Fallback: straight line
                    allCoordinates.append(originCoord)
                    allCoordinates.append(destCoord)

                    let straightLine = CLLocation(latitude: originCoord.latitude, longitude: originCoord.longitude)
                        .distance(from: CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude))
                    accDistance += straightLine
                    let speed: Double = transportType == .walking ? 1.39 : 8.33
                    accTime += straightLine / speed
                }

                calculationProgress = Double(i + 1) / Double(pairs)
                routePolylineCoordinates = allCoordinates
                totalDistance = accDistance
                totalTime = accTime
            }

            isCalculating = false
        }
    }

    // MARK: - Stop Management

    /// Removes a stop at the given index and recalculates directions if 2+ stops remain.
    /// - Parameter index: The zero-based index of the stop to remove.
    func removeStop(at index: Int) {
        guard stops.indices.contains(index) else { return }
        stops.remove(at: index)

        if stops.count >= 2 {
            calculateDirections()
        } else {
            routePolylineCoordinates = []
            totalDistance = 0
            totalTime = 0
        }
    }

    /// Changes the transport type and recalculates the route if it differs from the current value.
    func setTransportType(_ type: MKDirectionsTransportType) {
        guard type != transportType else { return }
        transportType = type
        if stops.count >= 2 {
            calculateDirections()
        }
    }

    /// Cancels the route task, clears all route data, and returns to the selection phase.
    func backToSelection() {
        currentTask?.cancel()
        showRoute = false
        stops = []
        routePolylineCoordinates = []
        totalDistance = 0
        totalTime = 0
    }

    // MARK: - Open in Apple Maps

    /// Opens the current route in Apple Maps using the ordered stop list and the active transport type.
    func openInAppleMaps() {
        let mapItems = stops.compactMap { salon -> MKMapItem? in
            guard let coord = salon.coordinate else { return nil }
            let placemark = MKPlacemark(coordinate: coord)
            let item = MKMapItem(placemark: placemark)
            item.name = salon.displayName
            return item
        }

        guard !mapItems.isEmpty else { return }

        let launchOptions: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: transportType == .walking
                ? MKLaunchOptionsDirectionsModeWalking
                : MKLaunchOptionsDirectionsModeDriving
        ]

        MKMapItem.openMaps(with: mapItems, launchOptions: launchOptions)
    }

    // MARK: - Error Handling

    private func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
