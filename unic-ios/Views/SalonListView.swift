//
//  SalonListView.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import SwiftUI

// MARK: - Glass Effect Modifier

struct GlassBackgroundModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        }
    }
}

extension View {
    func glassBackground<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackgroundModifier(shape: shape))
    }

    func glassBackgroundCapsule() -> some View {
        glassBackground(in: Capsule())
    }

    func glassBackgroundCircle() -> some View {
        glassBackground(in: Circle())
    }

    func glassBackgroundRectangle(cornerRadius: CGFloat? = nil) -> some View {
        if let cornerRadius {
            return AnyView(glassBackground(in: RoundedRectangle(cornerRadius: cornerRadius)))
        } else {
            return AnyView(glassBackground(in: Rectangle()))
        }
    }
}

// MARK: - Salon List View

struct SalonListView: View {
    @StateObject private var viewModel = SalonsViewModel()
    @State private var showRoutePlanner = false
    @State private var showAddSalon = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Content: List or Map
                if viewModel.isLoading {
                    ProgressView("loading")
                        .frame(maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error) {
                        viewModel.retry()
                    }
                } else if viewModel.showMap {
                    SalonMapView(viewModel: viewModel)
                } else {
                    List(viewModel.displayedSalons) { salon in
                        NavigationLink {
                            SalonDetailView(
                                salon: salon,
                                onSalonUpdated: { viewModel.updateSalon($0) },
                                onSalonDeleted: { viewModel.deleteSalon(salon) }
                            )
                        } label: {
                            SalonRowView(salon: salon)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.loadSalons()
                    }
                    .searchable(text: $viewModel.searchText, prompt: Text("search_salons"))
                    .safeAreaInset(edge: .bottom) {
                        VStack {
                            // Stats Header
                            StatsHeaderView(viewModel: viewModel)
                                .padding(.horizontal)

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
            }
                .navigationTitle("UNIC CRM")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if !viewModel.showMap {
                        ToolbarItem(placement: .topBarLeading) {
                            HStack(spacing: 16) {
                                Button {
                                    viewModel.showSortPopover = true
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .imageScale(.large)
                                }
                                .popover(isPresented: $viewModel.showSortPopover) {
                                    SortPopoverView(viewModel: viewModel)
                                        .presentationCompactAdaptation(.popover)
                                }

                                Button {
                                    viewModel.showFilterPopover = true
                                } label: {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .symbolVariant(viewModel.typeOptions.hasSelection ? .fill : .none)
                                        .imageScale(.large)
                                }
                                .popover(isPresented: $viewModel.showFilterPopover) {
                                    TypeFilterPopoverView(viewModel: viewModel)
                                        .presentationCompactAdaptation(.popover)
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                showAddSalon = true
                            } label: {
                                Image(systemName: "plus")
                                    .imageScale(.large)
                            }

                            Button {
                                showRoutePlanner = true
                            } label: {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                    .imageScale(.large)
                            }
                            .disabled(viewModel.displayedSalons.filter { $0.coordinate != nil }.count < 2)

                            Button {
                                withAnimation {
                                    viewModel.showMap.toggle()
                                }
                            } label: {
                                Image(systemName: viewModel.showMap ? "list.bullet" : "map")
                                    .imageScale(.large)
                            }
                        }
                    }
                }
                .task {
                    await viewModel.loadSalonsIfNeeded()
                }
                .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.alertMessage)
                }
                .sheet(isPresented: $showRoutePlanner) {
                    RoutePlannerView(salons: viewModel.displayedSalons, isPresented: $showRoutePlanner)
                }
                .sheet(isPresented: $showAddSalon) {
                    SalonFormView { salon in
                        viewModel.addSalon(salon)
                    }
                }
        }
    }
}

// MARK: - Stats Header

struct StatsHeaderView: View {
    @ObservedObject var viewModel: SalonsViewModel

    var body: some View {
        HStack(spacing: 16) {
            StatBadge(title: String(localized: "stat_total"), value: viewModel.totalCount, color: .blue)
            StatBadge(title: String(localized: "stat_new"), value: viewModel.newCount, color: .green)
            StatBadge(title: String(localized: "stat_contacted"), value: viewModel.contactedCount, color: .orange)
            StatBadge(title: String(localized: "stat_clients"), value: viewModel.orderedCount, color: .mint)
        }
    }
}

struct StatBadge: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Chips

struct FilterChipsView: View {
    @Binding var statusOptions: Options<SalonStatus>
    @Binding var showStatusInfo: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Status info button
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

                // Status "All" chip
                FilterChip(title: String(localized: "filter_all"), isSelected: !statusOptions.hasSelection) {
                    statusOptions.clear()
                }

                // Status chips
                ForEach(statusOptions.all) { status in
                    FilterChip(
                        title: "\(status.emoji) \(status.displayName)",
                        isSelected: statusOptions.isSelected(status)
                    ) {
                        statusOptions.toggle(status)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// MARK: - Salon Row

struct SalonRowView: View {
    let salon: Salon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(salon.displayName)
                    .font(.headline)

                Spacer()

                StatusBadge(status: salon.statusEnum)
            }

            if let address = salon.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if salon.phoneNumber != nil {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if salon.instagramHandle != nil {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if salon.contacts?.facebook?.value != nil {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if salon.websiteURL != nil {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: SalonStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(8)
    }
}

// MARK: - Error View

// MARK: - Sort Popover

struct SortPopoverView: View {
    @ObservedObject var viewModel: SalonsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sort options
            VStack(alignment: .leading, spacing: 4) {
                Text("sorting")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ForEach(SalonSortOption.allCases) { option in
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.displayName)
                                .font(.subheadline)
                            Spacer()
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Direction
            HStack(spacing: 8) {
                Button {
                    viewModel.sortAscending = true
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline)
                        .frame(width: 28, height: 28)
                        .background(viewModel.sortAscending ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(viewModel.sortAscending ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.sortAscending = false
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.subheadline)
                        .frame(width: 28, height: 28)
                        .background(!viewModel.sortAscending ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(!viewModel.sortAscending ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 200)
    }
}

// MARK: - Type Filter Popover

struct TypeFilterPopoverView: View {
    @ObservedObject var viewModel: SalonsViewModel

    private var hasAnySelection: Bool {
        viewModel.categoryOptions.hasSelection || viewModel.typeOptions.hasSelection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("category")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if hasAnySelection {
                        Button(String(localized: "reset")) {
                            viewModel.categoryOptions.clear()
                            viewModel.typeOptions.clear()
                        }
                        .font(.caption)
                    }
                }

                // Categories
                if !viewModel.categoryOptions.all.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.categoryOptions.all) { category in
                            Button {
                                viewModel.categoryOptions.toggle(category)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: viewModel.categoryOptions.isSelected(category) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(viewModel.categoryOptions.isSelected(category) ? .accentColor : .secondary)
                                        .font(.subheadline)
                                    Text(category.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Separator
                if !viewModel.categoryOptions.all.isEmpty && !viewModel.typeOptions.all.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                }

                // Business Types
                if !viewModel.typeOptions.all.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.typeOptions.all) { type in
                            Button {
                                viewModel.typeOptions.toggle(type)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: viewModel.typeOptions.isSelected(type) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(viewModel.typeOptions.isSelected(type) ? .accentColor : .secondary)
                                        .font(.subheadline)
                                    Text(type.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Empty state
                if viewModel.categoryOptions.all.isEmpty && viewModel.typeOptions.all.isEmpty {
                    Text("no_data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 220)
    }
}

// MARK: - Close Button

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .imageScale(.large)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text(message)
                .multilineTextAlignment(.center)

            Button("retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Status Info View

struct StatusInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SalonStatus.allCases) { status in
                    StatusInfoRow(status: status)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("salon_statuses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

struct StatusInfoRow: View {
    let status: SalonStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.emoji)
                Text(status.fullDisplayName)
                    .font(.headline)
            }

            Text(status.infoDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(status.nextAction)
                .font(.caption)
                .foregroundColor(status.color)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

extension SalonStatus {
    var emoji: String {
        switch self {
        case .new: return "🆕"
        case .contacted: return "💬"
        case .demoScheduled: return "📅"
        case .testing: return "🧪"
        case .ordered: return "📦"
        case .lost: return "❌"
        }
    }

    var fullDisplayName: String {
        switch self {
        case .new: return String(localized: "status_new_full")
        case .contacted: return String(localized: "status_contacted_full")
        case .demoScheduled: return String(localized: "status_demo_full")
        case .testing: return String(localized: "status_testing_full")
        case .ordered: return String(localized: "status_ordered_full")
        case .lost: return String(localized: "status_lost_full")
        }
    }

    var infoDescription: String {
        switch self {
        case .new: return String(localized: "status_new_desc")
        case .contacted: return String(localized: "status_contacted_desc")
        case .demoScheduled: return String(localized: "status_demo_desc")
        case .testing: return String(localized: "status_testing_desc")
        case .ordered: return String(localized: "status_ordered_desc")
        case .lost: return String(localized: "status_lost_desc")
        }
    }

    var nextAction: String {
        switch self {
        case .new: return String(localized: "status_new_action")
        case .contacted: return String(localized: "status_contacted_action")
        case .demoScheduled: return String(localized: "status_demo_action")
        case .testing: return String(localized: "status_testing_action")
        case .ordered: return String(localized: "status_ordered_action")
        case .lost: return String(localized: "status_lost_action")
        }
    }
}

extension SalonStatus {
    var displayName: String {
        switch self {
        case .new: return String(localized: "status_new")
        case .contacted: return String(localized: "status_contacted")
        case .demoScheduled: return String(localized: "status_demo")
        case .testing: return String(localized: "status_testing")
        case .ordered: return String(localized: "status_ordered")
        case .lost: return String(localized: "status_lost")
        }
    }

    var color: Color {
        switch self {
        case .new: return .green
        case .contacted: return .orange
        case .demoScheduled: return .blue
        case .testing: return .purple
        case .ordered: return .mint
        case .lost: return .red
        }
    }
}

#Preview {
    SalonListView()
}
