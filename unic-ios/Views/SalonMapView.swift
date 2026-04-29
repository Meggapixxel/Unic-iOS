//
//  SalonMapView.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Manager

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Permission changed
    }
}

// MARK: - Salon Map View

struct SalonMapView: View {
    @ObservedObject var viewModel: SalonsViewModel
    @State private var selectedSalon: Salon?

    // Prague center coordinates
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
    ))

    var body: some View {
        Map(position: $position, selection: $selectedSalon) {
            UserAnnotation()

            ForEach(viewModel.displayedSalons.filter { $0.coordinate != nil }) { salon in
                if let coordinate = salon.coordinate {
                    Marker(salon.displayName, systemImage: markerIcon(for: salon.statusEnum), coordinate: coordinate)
                        .tint(salon.statusEnum.color)
                        .tag(salon)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            LocationManager.shared.requestPermission()
        }
        .sheet(item: $selectedSalon) { salon in
            NavigationStack {
                SalonDetailView(
                    salon: salon,
                    onSalonUpdated: { viewModel.updateSalon($0) },
                    onSalonDeleted: {
                        viewModel.deleteSalon(salon)
                        selectedSalon = nil
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton { selectedSalon = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                // Salon count
                Text("salons_on_map \(viewModel.displayedSalons.filter { $0.coordinate != nil }.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Filter Chips
                FilterChipsView(
                    statusOptions: $viewModel.statusOptions,
                    showStatusInfo: $viewModel.showStatusInfo
                )
            }
            .padding(.vertical)
            .glassBackgroundRectangle(cornerRadius: 20)
            .padding(.horizontal)
        }
        .sheet(isPresented: $viewModel.showStatusInfo) {
            StatusInfoView()
        }
    }

    private func markerIcon(for status: SalonStatus) -> String {
        switch status {
        case .new: return "sparkles"
        case .contacted: return "phone.fill"
        case .demoScheduled: return "calendar"
        case .testDrive: return "hourglass"
        case .ordered: return "checkmark.seal.fill"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: - Salon coordinate extension

extension Salon {
    var coordinate: CLLocationCoordinate2D? {
        guard let location = maps?.location else { return nil }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }
}

#Preview {
    SalonMapView(viewModel: SalonsViewModel())
}
