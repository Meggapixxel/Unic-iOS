//
//  RouteViewModel.swift
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

@MainActor
final class RouteViewModel: ObservableObject {

    // MARK: - Selection Phase

    @Published var availableSalons: [Salon] = []
    @Published var selectedIds: Set<String> = []
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

    @Published var stops: [Salon] = []
    @Published var routePolylineCoordinates: [CLLocationCoordinate2D] = []
    @Published var totalDistance: CLLocationDistance = 0
    @Published var totalTime: TimeInterval = 0
    @Published var transportType: MKDirectionsTransportType = .automobile
    @Published var isCalculating = false
    @Published var calculationProgress: Double = 0
    @Published var showRoute = false

    // Alert
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed

    var selectedCount: Int { selectedIds.count }
    var canBuildRoute: Bool { selectedIds.count >= 2 }

    var formattedDistance: String {
        let measurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

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

    func dismiss() {
        currentTask?.cancel()
        isPresented?.wrappedValue = false
    }

    // MARK: - Selection

    func toggleSelection(_ salon: Salon) {
        if selectedIds.contains(salon.salonId) {
            selectedIds.remove(salon.salonId)
        } else {
            selectedIds.insert(salon.salonId)
        }
    }

    func isSelected(_ salon: Salon) -> Bool {
        selectedIds.contains(salon.salonId)
    }

    func selectAll() {
        selectedIds = Set(availableSalons.map(\.salonId))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - Build Route

    func buildRoute() {
        let selected = availableSalons.filter { selectedIds.contains($0.salonId) }
        guard selected.count >= 2 else { return }

        stops = optimizeOrder(selected, startingFrom: userLocation)
        showRoute = true
        calculateDirections()
    }

    // MARK: - Nearest-Neighbor Optimization

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

    func setTransportType(_ type: MKDirectionsTransportType) {
        guard type != transportType else { return }
        transportType = type
        if stops.count >= 2 {
            calculateDirections()
        }
    }

    func backToSelection() {
        currentTask?.cancel()
        showRoute = false
        stops = []
        routePolylineCoordinates = []
        totalDistance = 0
        totalTime = 0
    }

    // MARK: - Open in Apple Maps

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
