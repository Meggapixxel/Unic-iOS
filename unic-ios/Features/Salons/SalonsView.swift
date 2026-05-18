// FILE: unic-ios/Features/Salons/SalonsView.swift

import ComposableArchitecture
import SwiftUI

/// Root view for the Salons tab, hosting the navigation stack and all salon list UI.
struct SalonsView: View {
    @Bindable var store: StoreOf<SalonsFeature>

    var body: some View {
        mainContent
            .searchable(text: $store.searchText, prompt: Text(String.search_salons))
            .task { store.send(.onLoad) }
            .sheet(
                item: $store.scope(state: \.destination?.form, action: \.destination.form)
            ) { formStore in
                SalonFormView(store: formStore)
            }
            .fullScreenCover(
                item: $store.scope(state: \.destination?.routePlanner, action: \.destination.routePlanner)
            ) { rpStore in
                RoutePlannerView(store: rpStore)
            }
    }

    // MARK: - Main Content

    /// Renders a loading spinner, an error view, the map view, or the salon list depending on current state.
    @ViewBuilder
    private var mainContent: some View {
        if store.isLoading {
            ProgressView(String.loading)
                .frame(maxHeight: .infinity)
        } else if let error = store.errorMessage {
            ErrorView(message: error) {
                store.send(.onLoad)
            }
        } else if store.showMap {
            SalonsMapView(store: store)
        } else {
            salonList
        }
    }

    // MARK: - List

    /// Plain list of displayed salons with a stats/filter footer and the test-drive navigation row.
    private var salonList: some View {
        List {
            Section {
                Button {
                    store.send(.navigateToTestDrive)
                } label: {
                    TestDriveListRow(count: store.statCounts.testDrive)
                }
                .buttonStyle(.plain)
            }

            ForEach(store.displayedSalons) { salon in
                Button {
                    store.send(.salonTapped(salon))
                } label: {
                    SalonRowView(salon: salon)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .refreshable {
            store.send(.onLoad)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                StatsRow(counts: store.statCounts)
                    .padding(.horizontal)
                    .padding(.top, 12)

                StatusFilterChipsView(
                    statusFilter: $store.statusFilter,
                    showStatusInfo: $store.showStatusInfo
                )
                .padding(.vertical, 8)
            }
            .glassBackgroundRectangle(cornerRadius: 20)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $store.showStatusInfo) {
            StatusInfoView(isPresented: $store.showStatusInfo)
        }
    }

}

// MARK: - TabChildView

extension SalonsView: TabChildView {
    var tabTitle: String { "Salons" }

    @ToolbarContentBuilder var tabToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.showFilterPopover = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .symbolVariant(store.hasAnyFilter ? .fill : .none)
                    .imageScale(.large)
            }
            .popover(isPresented: $store.showFilterPopover) {
                SalonsFilterPopoverView(store: store)
                    .presentationCompactAdaptation(.popover)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button { store.send(.openAdd) } label: {
                    Image(systemName: "plus").imageScale(.large)
                }
                Button {
                    store.send(.navigateToRoutePlanner)
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .imageScale(.large)
                }
                .disabled(store.displayedSalons.filter { $0.coordinate != nil }.count < 2)
                Button {
                    withAnimation { store.showMap.toggle() }
                } label: {
                    Image(systemName: store.showMap ? "list.bullet" : "map")
                        .imageScale(.large)
                }
            }
        }
    }
}

// MARK: - Stats Row

/// Horizontal row of coloured stat badges summarising salon counts by category.
private struct StatsRow: View {
    let counts: SalonsFeature.State.StatCounts

    var body: some View {
        HStack(spacing: 16) {
            StatBadge(title: String.stat_total, value: counts.total, color: .blue)
            StatBadge(title: String.stat_new, value: counts.new, color: .green)
            StatBadge(title: String.stat_contacted, value: counts.contacted, color: .orange)
            StatBadge(title: String.stat_clients, value: counts.ordered, color: .mint)
        }
    }
}

// MARK: - Status Filter Chips

/// Horizontally scrollable chip strip for filtering the salon list by status, with a help button.
private struct StatusFilterChipsView: View {
    @Binding var statusFilter: Set<SalonStatus>
    @Binding var showStatusInfo: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showStatusInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }

                FilterChip(title: String.filter_all, isSelected: statusFilter.isEmpty) {
                    statusFilter.removeAll()
                }

                ForEach(SalonStatus.allCases) { status in
                    FilterChip(
                        title: "\(status.emoji) \(status.displayName)",
                        isSelected: statusFilter.contains(status)
                    ) {
                        if statusFilter.contains(status) {
                            statusFilter.remove(status)
                        } else {
                            statusFilter.insert(status)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Filter Popover

/// Popover containing sort options (with direction toggle), date-added ranges, and language filters.
private struct SalonsFilterPopoverView: View {
    @Bindable var store: StoreOf<SalonsFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    if store.hasAnyFilter {
                        Button(String.reset) {
                            store.send(.clearFilters)
                        }
                        .font(.caption)
                    }
                }

                // Sort
                FilterSection(title: String.sorting) {
                    ForEach(SalonSortOption.allCases) { option in
                        FilterRow(
                            title: option.displayName,
                            isSelected: store.sortOption == option
                        ) { store.sortOption = option }
                    }
                    HStack(spacing: 8) {
                        Button {
                            store.sortAscending = true
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.subheadline)
                                .frame(width: 28, height: 28)
                                .background(store.sortAscending ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(store.sortAscending ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.sortAscending = false
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.subheadline)
                                .frame(width: 28, height: 28)
                                .background(!store.sortAscending ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(!store.sortAscending ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                // Date Added
                FilterSection(title: String.filter_date_added) {
                    ForEach(DateRangeOption.allCases) { range in
                        FilterRow(
                            title: range.displayName,
                            isSelected: store.dateRangeFilter.contains(range.id)
                        ) {
                            if store.dateRangeFilter.contains(range.id) {
                                store.dateRangeFilter.remove(range.id)
                            } else {
                                store.dateRangeFilter.insert(range.id)
                            }
                        }
                    }
                }

                // Language
                if !store.availableLanguages.isEmpty {
                    FilterSection(title: String.filter_language) {
                        ForEach(store.availableLanguages) { lang in
                            FilterRow(
                                title: lang.displayName,
                                isSelected: store.languageFilter.contains(lang.id)
                            ) {
                                if store.languageFilter.contains(lang.id) {
                                    store.languageFilter.remove(lang.id)
                                } else {
                                    store.languageFilter.insert(lang.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 240)
    }
}

// MARK: - Map View

/// Full-screen native map showing filtered salon pins with status colours and a "center on user" button.
private struct SalonsMapView: View {
    @Bindable var store: StoreOf<SalonsFeature>
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var centerOnUser = false

    /// Number of currently displayed salons that have a geocoded coordinate.
    private var mappedCount: Int {
        store.displayedSalons.filter { $0.coordinate != nil }.count
    }

    var body: some View {
        SalonNativeMapView(
            salons: Array(store.displayedSalons),
            onSelect: { store.send(.salonTapped($0)) },
            centerOnUser: $centerOnUser
        )
        .ignoresSafeArea()
        .onAppear {
            if !locationManager.isAuthorized {
                LocationManager.shared.requestPermission()
            }
        }
        .overlay(alignment: .topTrailing) {
            if locationManager.isAuthorized {
                Button {
                    centerOnUser = true
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(12)
                        .glassBackgroundCircle()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("salons_on_map \(mappedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusFilterChipsView(
                    statusFilter: $store.statusFilter,
                    showStatusInfo: $store.showStatusInfo
                )
            }
            .padding(.vertical)
            .glassBackgroundRectangle(cornerRadius: 20)
            .padding(.horizontal)
        }
        .sheet(isPresented: $store.showStatusInfo) {
            StatusInfoView(isPresented: $store.showStatusInfo)
        }
    }
}
