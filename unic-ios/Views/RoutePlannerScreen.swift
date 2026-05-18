//
//  RoutePlannerScreen.swift
//  unic-ios
//
//  Created by UNIC Team on 31/03/2026.
//

import SwiftUI
import MapKit
import IdentifiedCollections

/// Two-phase modal screen: first the user selects salons (list or map), then sees the optimized route on a map.
struct RoutePlannerScreen: View {
    @StateObject private var viewModel: RouteViewModel

    init(salons: IdentifiedArrayOf<Salon>, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: RouteViewModel(salons: salons, isPresented: isPresented))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showRoute {
                    routeMapView
                } else {
                    selectionView
                }
            }
            .navigationTitle(viewModel.showRoute ? "route_planner" : "route_select_salons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.showRoute {
                        Button {
                            viewModel.backToSelection()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    } else {
                        Button {
                            withAnimation {
                                viewModel.showSelectionMap.toggle()
                            }
                        } label: {
                            Image(systemName: viewModel.showSelectionMap ? "list.bullet" : "map")
                                .imageScale(.large)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { viewModel.dismiss() }
                }
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }


        }
    }

    // MARK: - Selection View

    private var selectionView: some View {
        Group {
            if viewModel.showSelectionMap {
                selectionMapContent
            } else {
                selectionListContent
            }
        }
        .safeAreaInset(edge: .bottom) {
            selectionBottomBar
        }
    }

    // MARK: - Selection List

    private var selectionListContent: some View {
        List {
            ForEach(viewModel.availableSalons, id: \.salonId) { salon in
                Button {
                    viewModel.toggleSelection(salon)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isSelected(salon) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(viewModel.isSelected(salon) ? .accentColor : .secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(salon.displayName)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            if let address = salon.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        StatusBadge(status: salon.statusEnum)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Selection Map

    private var selectionMapContent: some View {
        Map(position: $viewModel.selectionMapPosition) {
            UserAnnotation()

            ForEach(viewModel.availableSalons, id: \.salonId) { salon in
                if let coordinate = salon.coordinate {
                    Annotation(salon.displayName, coordinate: coordinate) {
                        Button {
                            viewModel.toggleSelection(salon)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isSelected(salon) ? Color.accentColor : Color(.systemGray4))
                                    .frame(width: 30, height: 30)
                                    .shadow(radius: 2)

                                if viewModel.isSelected(salon) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .fill(salon.statusEnum.color)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Selection Bottom Bar

    private var selectionBottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("route_selected \(viewModel.selectedCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button(String.route_deselect_all) {
                    viewModel.deselectAll()
                }
                .font(.caption)
                .opacity(viewModel.selectedCount > 0 ? 1 : 0)
            }
            .padding(.horizontal)

            Button {
                viewModel.buildRoute()
            } label: {
                Label("route_build", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canBuildRoute)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .glassBackgroundRectangle(cornerRadius: 20)
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Route Map View

    private var routeMapView: some View {
        Map(position: .constant(.automatic)) {
            UserAnnotation()

            if !viewModel.routePolylineCoordinates.isEmpty {
                MapPolyline(coordinates: viewModel.routePolylineCoordinates)
                    .stroke(
                        viewModel.transportType == .automobile ? Color.blue : Color.orange,
                        lineWidth: 5
                    )
            }

            ForEach(Array(viewModel.stops.enumerated()), id: \.element.salonId) { index, salon in
                if let coordinate = salon.coordinate {
                    Annotation(salon.displayName, coordinate: coordinate) {
                        ZStack {
                            Circle()
                                .fill(salon.statusEnum.color)
                                .frame(width: 32, height: 32)
                                .shadow(radius: 2)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            routeBottomPanel
        }
    }

    // MARK: - Route Bottom Panel

    private var routeBottomPanel: some View {
        VStack(spacing: 12) {
            Picker("route_transport", selection: Binding(
                get: { viewModel.transportType == .automobile ? 0 : 1 },
                set: { viewModel.setTransportType($0 == 0 ? .automobile : .walking) }
            )) {
                Label("route_driving", systemImage: "car.fill").tag(0)
                Label("route_walking", systemImage: "figure.walk").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewModel.stops.count >= 2 {
                HStack(spacing: 16) {
                    RouteStatBadge(
                        title: String.route_distance,
                        value: viewModel.formattedDistance,
                        icon: "arrow.triangle.swap"
                    )
                    RouteStatBadge(
                        title: String.route_time,
                        value: viewModel.formattedTime,
                        icon: "clock"
                    )
                    RouteStatBadge(
                        title: String.route_stops,
                        value: "\(viewModel.stops.count)",
                        icon: "mappin.and.ellipse"
                    )
                }
                .padding(.horizontal)
            }

            if viewModel.isCalculating {
                ProgressView(value: viewModel.calculationProgress)
                    .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.stops.enumerated()), id: \.element.salonId) { index, salon in
                        RouteStopChip(
                            index: index + 1,
                            salon: salon,
                            onRemove: { viewModel.removeStop(at: index) }
                        )
                    }
                }
                .padding(.horizontal)
            }

            Button {
                viewModel.openInAppleMaps()
            } label: {
                Label("route_navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.stops.count < 2)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .glassBackgroundRectangle(cornerRadius: 20)
        .padding(.horizontal)
    }

}

// MARK: - Route Stat Badge

/// Small vertical badge displaying a route statistic (distance, time, or stop count).
struct RouteStatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Route Stop Chip

/// Horizontally scrollable chip showing a stop's order number, name, and a remove button.
struct RouteStopChip: View {
    /// 1-based position in the route.
    let index: Int
    let salon: Salon
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(salon.statusEnum.color)
                .clipShape(Circle())

            Text(salon.displayName)
                .font(.caption)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray5))
        .cornerRadius(16)
    }
}

#Preview {
    RoutePlannerScreen(salons: IdentifiedArrayOf<Salon>(), isPresented: .constant(true))
}
