import ComposableArchitecture
import MapKit
import SwiftUI

struct UserActivityView: View {
    @Bindable var store: StoreOf<UserActivityFeature>

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // MARK: Date controls
                VStack(spacing: 10) {
                    Picker("", selection: $store.groupMode) {
                        Text(String.activity_group_day).tag(UserActivityFeature.State.GroupMode.day)
                        Text(String.activity_group_custom).tag(UserActivityFeature.State.GroupMode.custom)
                    }
                    .pickerStyle(.segmented)

                    if store.groupMode == .day {
                        DatePicker(
                            String.activity_group_day,
                            selection: $store.selectedDate,
                            in: ...store.maxDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String.activity_from)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                DatePicker("", selection: $store.customStart, in: ...store.customEnd, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String.activity_to)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                DatePicker("", selection: $store.customEnd, in: store.customStart...store.maxDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                // MARK: Stats
                let counts = store.filteredStatusCounts
                if !counts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(SalonStatus.allCases) { status in
                                if let count = counts[status] {
                                    StatChip(status: status, count: count)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, -16)
                }

                // MARK: Entries
                if store.filteredEntriesByDay.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        store.entries.isEmpty ? String.activity_empty : String.activity_no_data,
                        systemImage: store.entries.isEmpty ? "clock.arrow.circlepath" : "calendar.badge.minus"
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(store.filteredEntriesByDay, id: \.0) { date, dayEntries in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sectionHeader(date))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            let routeEntries = dayEntries
                                .filter { $0.coordinate != nil }
                                .sorted { $0.timestamp < $1.timestamp }
                            if !routeEntries.isEmpty {
                                RouteMapView(entries: routeEntries)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            VStack(spacing: 8) {
                                ForEach(dayEntries) { entry in
                                    ActivityEntryCard(entry: entry)
                                        .contextMenu {
                                            if store.canDeleteActivity {
                                                Button(role: .destructive) {
                                                    store.send(.deleteConfirmed(entry))
                                                } label: {
                                                    Label(String.delete, systemImage: "trash")
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.user.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.send(.navigateToPlans) } label: {
                    Image(systemName: "target")
                }
            }
        }
        .overlay {
            if store.isLoading { ProgressView() }
        }
        .task { store.send(.onLoad) }
    }

    private func sectionHeader(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        if cal.isDateInToday(date) { return String.activity_today }
        if cal.isDateInYesterday(date) { return String.activity_yesterday }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
    let status: SalonStatus
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(status.color)
            Text(status.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 60)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Activity Entry Card

private struct ActivityEntryCard: View {
    let entry: UserActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(entry.status.color)
                .frame(width: 4)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.salonName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(entry.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(entry.status.color.opacity(0.12), in: Capsule())

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Spacer(minLength: 0)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Route Map

private struct RouteMapView: View {
    let entries: [UserActivityEntry]

    @State private var position: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        entries.compactMap(\.coordinate)
    }

    private func makeRegion() -> MKCoordinateRegion {
        let coords = coordinates
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.075, longitude: 14.438),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let centerLat = (lats.min()! + lats.max()!) / 2
        let centerLng = (lngs.min()! + lngs.max()!) / 2
        let spanLat = max((lats.max()! - lats.min()!) * 1.6, 0.012)
        let spanLng = max((lngs.max()! - lngs.min()!) * 1.6, 0.012)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLng)
        )
    }

    var body: some View {
        Map(position: $position) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if let coord = entry.coordinate {
                    Annotation(entry.salonName, coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(entry.status.color)
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue.opacity(0.6), lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .disabled(true)
        .onAppear { position = .region(makeRegion()) }
        .onChange(of: entries) { position = .region(makeRegion()) }
    }
}
