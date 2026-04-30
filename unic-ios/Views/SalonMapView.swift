//
//  SalonMapView.swift
//  unic-ios
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}

// MARK: - Annotation Model

final class SalonAnnotation: NSObject, MKAnnotation {
    let salon: Salon
    let coordinate: CLLocationCoordinate2D

    init(salon: Salon, coordinate: CLLocationCoordinate2D) {
        self.salon = salon
        self.coordinate = coordinate
    }

    var title: String? { salon.displayName }
}

// MARK: - UIViewRepresentable

struct SalonNativeMapView: UIViewRepresentable {
    let salons: [Salon]
    let onSelect: (Salon) -> Void

    private static let annotationId  = "SalonPin"
    private static let clusterPrefix = "SalonCluster"

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            ),
            animated: false
        )
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.annotationId)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let existing = map.annotations.compactMap { $0 as? SalonAnnotation }
        let existingIds = Set(existing.map { $0.salon.salonId })
        let newIds = Set(salons.compactMap { $0.coordinate != nil ? $0.salonId : nil })

        if existingIds == newIds { return }

        map.removeAnnotations(existing)
        let annotations = salons.compactMap { salon -> SalonAnnotation? in
            guard let c = salon.coordinate else { return nil }
            return SalonAnnotation(salon: salon, coordinate: c)
        }
        map.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelect: (Salon) -> Void
        init(onSelect: @escaping (Salon) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as! MKMarkerAnnotationView
                view.markerTintColor = .systemGray
                view.titleVisibility = .adaptive
                view.canShowCallout = false
                return view
            }

            guard let salonAnnotation = annotation as? SalonAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: SalonNativeMapView.annotationId,
                for: salonAnnotation
            ) as! MKMarkerAnnotationView

            let uiColor = UIColor(salonAnnotation.salon.statusEnum.color)
            view.markerTintColor = uiColor
            view.glyphImage = nil
            view.glyphText = nil
            view.titleVisibility = .hidden
            view.clusteringIdentifier = SalonNativeMapView.clusterPrefix
            view.displayPriority = .required
            view.canShowCallout = true

            // Left: open details
            let detailBtn = UIButton(type: .detailDisclosure)
            view.leftCalloutAccessoryView = detailBtn

            // Right: navigate in Google Maps
            let navBtn = UIButton(type: .system)
            navBtn.setImage(UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill"), for: .normal)
            navBtn.tintColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            navBtn.sizeToFit()
            view.rightCalloutAccessoryView = navBtn

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)
                var region = mapView.region
                region.span.latitudeDelta  /= 3
                region.span.longitudeDelta /= 3
                region.center = cluster.coordinate
                mapView.setRegion(region, animated: true)
            }
            // salon pin — leave selected so callout shows
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let salonAnnotation = view.annotation as? SalonAnnotation else { return }
            let salon = salonAnnotation.salon

            if control == view.leftCalloutAccessoryView {
                // Open detail sheet
                mapView.deselectAnnotation(salonAnnotation, animated: true)
                onSelect(salon)
            } else if control == view.rightCalloutAccessoryView {
                // Navigate in Google Maps (fallback to Apple Maps)
                let coord = salonAnnotation.coordinate
                let name = salon.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let googleUrl = URL(string: "comgooglemaps://?daddr=\(coord.latitude),\(coord.longitude)&directionsmode=driving")
                let appleUrl = URL(string: "maps://?daddr=\(coord.latitude),\(coord.longitude)&q=\(name)")
                if let google = googleUrl, UIApplication.shared.canOpenURL(google) {
                    UIApplication.shared.open(google)
                } else if let apple = appleUrl {
                    UIApplication.shared.open(apple)
                }
            }
        }
    }
}

// MARK: - Salon Map View

struct SalonMapView: View {
    @ObservedObject var viewModel: SalonsViewModel
    @State private var selectedSalon: Salon?

    private var mappedCount: Int {
        viewModel.displayedSalons.filter { $0.coordinate != nil }.count
    }

    var body: some View {
        SalonNativeMapView(salons: Array(viewModel.displayedSalons)) { salon in
            selectedSalon = salon
        }
        .ignoresSafeArea()
        .onAppear {
            LocationManager.shared.requestPermission()
        }
        .sheet(item: $selectedSalon) { salon in
            NavigationStack {
                SalonDetailView(
                    salon: salon,
                    showMap: false,
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
                Text("salons_on_map \(mappedCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)

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
