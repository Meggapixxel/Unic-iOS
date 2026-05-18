import ComposableArchitecture
import MapKit
import SwiftUI

/// Horizontally pageable activity screen for a single user.
/// Each page corresponds to one plan period (newest first), showing rings, status stats, and a day-by-day timeline.
struct UserActivityView: View {
    @Bindable var store: StoreOf<UserActivityFeature>

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.planPeriods.isEmpty {
                ContentUnavailableView(String.activity_empty, systemImage: "clock.arrow.circlepath")
            } else {
                TabView(selection: $store.selectedPlanIndex) {
                    ForEach(Array(store.planPeriods.enumerated()), id: \.offset) { index, period in
                        PlanPeriodPageView(
                            period: period,
                            entries: index < store.entriesByPlan.count ? store.entriesByPlan[index] : [],
                            canDelete: store.canDeleteActivity,
                            canManagePlans: store.canManagePlans,
                            onDelete: { entry in store.send(.deleteConfirmed(entry)) },
                            onEditPlan: { store.send(.editPlanTapped(period)) }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.user.fullName)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if store.isLoading { ProgressView() }
        }
        .task { store.send(.onLoad) }
        .sheet(
            item: $store.scope(state: \.destination?.editPlan, action: \.destination.editPlan)
        ) { formStore in
            PlansFormView(store: formStore)
        }
    }
}

// MARK: - Plan Period Page

private struct PlanPeriodPageView: View {
    let period: PlanPeriod
    let entries: [UserActivityEntry]
    let canDelete: Bool
    let canManagePlans: Bool
    let onDelete: (UserActivityEntry) -> Void
    let onEditPlan: () -> Void

    private var statusCounts: [SalonStatus: Int] {
        Dictionary(grouping: entries, by: \.status).mapValues(\.count)
    }

    private var entriesByDay: [(Date, [UserActivityEntry])] {
        let cal = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        return grouped.sorted { $0.key > $1.key }
    }

    private var salonsCount: Int { entries.count }
    private var testDrivesCount: Int { entries.filter { $0.status == .testDrive }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Period header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(planPeriodString(from: period.startDate, to: period.endDate))
                            .font(.headline)
                        Spacer()
                        periodBadge
                        if canManagePlans {
                            Image(systemName: "square.and.pencil")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(period.daysTotal) \(String.day_abbr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { if canManagePlans { onEditPlan() } }

                // MARK: Rings
                let hasTotalRings = (period.targetSalons ?? 0) > 0 || (period.targetTestDrives ?? 0) > 0
                let hasDayRings   = period.isActive && (period.targetSalonsPerDay > 0 || period.targetTestDrivesPerDay > 0)

                if hasTotalRings || hasDayRings {
                    VStack(alignment: .leading, spacing: 12) {
                        if hasTotalRings {
                            Text(String.plan_goal_total)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 40) {
                                if let target = period.targetSalons, target > 0 {
                                    RingProgressView(
                                        value: salonsCount,
                                        target: target,
                                        label: String.plan_target_salons,
                                        color: period.isPast ? .secondary : .blue
                                    )
                                }
                                if let target = period.targetTestDrives, target > 0 {
                                    RingProgressView(
                                        value: testDrivesCount,
                                        target: target,
                                        label: String.plan_target_test_drives,
                                        color: period.isPast ? .secondary : .green
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if hasDayRings {
                            Text(String.activity_today)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 40) {
                                if period.targetSalonsPerDay > 0 {
                                    RingProgressView(
                                        value: todaySalons,
                                        target: period.targetSalonsPerDay,
                                        label: String.plan_target_salons,
                                        color: .blue
                                    )
                                }
                                if period.targetTestDrivesPerDay > 0 {
                                    RingProgressView(
                                        value: todayTestDrives,
                                        target: period.targetTestDrivesPerDay,
                                        label: String.plan_target_test_drives,
                                        color: .green
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                // MARK: Status chips
                if !statusCounts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(SalonStatus.allCases) { status in
                                if let count = statusCounts[status] {
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
                if entries.isEmpty {
                    ContentUnavailableView(
                        String.activity_no_data,
                        systemImage: "calendar.badge.minus"
                    )
                    .padding(.top, 20)
                } else {
                    ForEach(entriesByDay, id: \.0) { date, dayEntries in
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
                                            if canDelete {
                                                Button(role: .destructive) {
                                                    onDelete(entry)
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
            .padding(.top, 12)
            .padding(.bottom, 48) // space for page indicator dots
        }
    }

    // MARK: Helpers

    private var todaySalons: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        return entries.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }.count
    }

    private var todayTestDrives: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        return entries.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay && $0.status == .testDrive }.count
    }

    @ViewBuilder
    private var periodBadge: some View {
        if period.isActive {
            Text("● \(String.plan_status_active)").font(.caption.bold()).foregroundStyle(.green)
        } else if period.isPast {
            Text("✓ \(String.plan_status_done)").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("◌ \(String.plan_status_upcoming)").font(.caption).foregroundStyle(.orange)
        }
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
                        AvatarCircle(text: "\(index + 1)", color: entry.status.color, size: 28)
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
