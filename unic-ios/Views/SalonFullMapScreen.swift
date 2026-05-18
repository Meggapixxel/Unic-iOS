//
//  SalonFullMapScreen.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import SwiftUI
import MapKit

/// Full-screen map for a single salon with style picker, navigation to Google Maps, and an info card.
struct SalonFullMapScreen: View {
    let salon: Salon

    @State private var position: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyle = .standard

    var body: some View {
        ZStack {
            if let coordinate = salon.coordinate {
                Map(position: $position) {
                    Marker(salon.displayName, systemImage: "scissors", coordinate: coordinate)
                        .tint(salon.statusEnum.color)
                }
                .mapStyle(mapStyle)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                    MapPitchToggle()
                }
                .onAppear {
                    position = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            } else {
                ContentUnavailableView(
                    "no_coordinates",
                    systemImage: "map.fill",
                    description: Text("no_location_data")
                )
            }
        }
        .navigationInlineTitle(salon.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        mapStyle = .standard
                    } label: {
                        Label("map_standard", systemImage: "map")
                    }

                    Button {
                        mapStyle = .imagery
                    } label: {
                        Label("map_satellite", systemImage: "globe.americas")
                    }

                    Button {
                        mapStyle = .hybrid
                    } label: {
                        Label("map_hybrid", systemImage: "map.fill")
                    }
                } label: {
                    Image(systemName: "map.circle")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if let url = salon.googleMapsURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Salon info card at bottom
            salonInfoCard
        }
    }

    private var salonInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(salon.displayName)
                        .font(.headline)

                    if let address = salon.address {
                        HStack(spacing: 4) {
                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button {
                                UIPasteboard.general.string = address
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                StatusBadge(status: salon.statusEnum)
            }

            HStack(spacing: 12) {
                if let phone = salon.phoneNumber {
                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("call", systemImage: "phone.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .contextMenu {
                        Text(phone)
                            .font(.headline)

                        Button {
                            UIPasteboard.general.string = phone
                        } label: {
                            Label("copy_number", systemImage: "doc.on.doc")
                        }

                        Button {
                            if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("call", systemImage: "phone.fill")
                        }
                    }
                }

                if let url = salon.googleMapsURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Google Maps", systemImage: "map.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}

//#Preview {
//    NavigationStack {
//        SalonFullMapScreen(salon: Salon(
//            salonId: "test",
//            name: "Test Salon",
//            city: "Prague",
//            address: "Test Address 123",
//            categoryName: "Hair Salon",
//            category: ["hair"],
//            tags: [],
//            maps: Maps(provider: "google", mapsUrl: "https://maps.google.com", placeId: "test", location: Location(lat: 50.0755, lng: 14.4378), source: "excel", confidence: 1.0),
//            contacts: nil,
//            leadTemp: nil,
//            status: "new",
//            ownerDriven: nil,
//            notes: nil,
//            nextStep: nil,
//            source: nil,
//            enrichmentStatus: nil,
//            enrichmentBatch: nil,
//            googlePlacesTypes: nil
//        ))
//    }
//}
