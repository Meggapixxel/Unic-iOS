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
    @State private var salonPath: [Salon] = []

    var body: some View {
        NavigationStack(path: $salonPath) {
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
                    List {
                        Section {
                            NavigationLink {
                                TestDriveView(
                                    salons: Array(viewModel.salons),
                                    onSalonUpdated: { viewModel.updateSalon($0) },
                                    onSalonDeleted: { viewModel.deleteSalon($0) }
                                )
                            } label: {
                                TestDriveListRow(count: viewModel.testDriveCount)
                            }
                        }

                        ForEach(viewModel.displayedSalons) { salon in
                            NavigationLink(value: salon) {
                                SalonRowView(salon: salon)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(for: Salon.self) { salon in
                        SalonDetailView(
                            salon: salon,
                            onSalonUpdated: { viewModel.updateSalon($0) },
                            onSalonDeleted: { viewModel.deleteSalon(salon); salonPath.removeLast() }
                        )
                    }
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
                        .padding()
                    }
                    .sheet(isPresented: $viewModel.showStatusInfo) {
                        StatusInfoView(isPresented: $viewModel.showStatusInfo)
                    }
                }
            }
                .navigationTitle("Salons")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.showFilterPopover = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .symbolVariant(viewModel.hasAnyFilter ? .fill : .none)
                                .imageScale(.large)
                        }
                        .popover(isPresented: $viewModel.showFilterPopover) {
                            FilterSortPopoverView(viewModel: viewModel)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button { viewModel.openAddSalon() } label: {
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
                .sheet(
                    isPresented: Binding(
                        get: { viewModel.salonFormVM != nil },
                        set: { if !$0 { viewModel.closeAddSalon() } }
                    ),
                    onDismiss: { viewModel.closeAddSalon() }
                ) {
                    if let formVM = viewModel.salonFormVM {
                        SalonFormView(viewModel: formVM)
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
            StatBadge(title: String.stat_total, value: viewModel.totalCount, color: .blue)
            StatBadge(title: String.stat_new, value: viewModel.newCount, color: .green)
            StatBadge(title: String.stat_contacted, value: viewModel.contactedCount, color: .orange)
            StatBadge(title: String.stat_clients, value: viewModel.orderedCount, color: .mint)
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
                FilterChip(title: String.filter_all, isSelected: !statusOptions.hasSelection) {
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

// MARK: - Test Drive List Row

struct TestDriveListRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flask.fill")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(String.test_drive)
                    .font(.headline)
                Text("\(count) \(String.stat_total.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
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

                if let lang = salon.language, !lang.isEmpty {
                    Text(flagEmoji(for: lang))
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private func flagEmoji(for languageCode: String) -> String {
    let regionCode: String
    switch languageCode.prefix(2).lowercased() {
    case "uk": regionCode = "UA"
    case "ru": regionCode = "RU"
    case "cs": regionCode = "CZ"
    case "sk": regionCode = "SK"
    case "pl": regionCode = "PL"
    case "de": regionCode = "DE"
    case "fr": regionCode = "FR"
    case "it": regionCode = "IT"
    case "es": regionCode = "ES"
    default:   regionCode = Locale(identifier: languageCode).region?.identifier ?? "UN"
    }
    let base: UInt32 = 127397
    return regionCode.uppercased().unicodeScalars
        .compactMap { Unicode.Scalar(base + $0.value).map(String.init) }
        .joined()
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

// MARK: - Combined Filter + Sort Popover

struct FilterSortPopoverView: View {
    @ObservedObject var viewModel: SalonsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Spacer()
                    if viewModel.hasAnyFilter {
                        Button(String.reset) {
                            viewModel.languageOptions.clear()
                            viewModel.dateRangeOptions.clear()
                        }
                        .font(.caption)
                    }
                }

                // Sort
                FilterSection(title: String.sorting) {
                    ForEach(SalonSortOption.allCases) { option in
                        FilterRow(
                            title: option.displayName,
                            isSelected: viewModel.sortOption == option
                        ) { viewModel.sortOption = option }
                    }
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
                    .padding(.top, 4)
                }

                // Date Added
                FilterSection(title: String.filter_date_added) {
                    ForEach(viewModel.dateRangeOptions.all) { range in
                        FilterRow(
                            title: range.displayName,
                            isSelected: viewModel.dateRangeOptions.isSelected(range)
                        ) { viewModel.dateRangeOptions.toggle(range) }
                    }
                }

                // Language
                if !viewModel.languageOptions.all.isEmpty {
                    FilterSection(title: String.filter_language) {
                        ForEach(viewModel.languageOptions.all) { lang in
                            FilterRow(
                                title: lang.displayName,
                                isSelected: viewModel.languageOptions.isSelected(lang)
                            ) { viewModel.languageOptions.toggle(lang) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 240)
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.uppercaseSmallCaps())
                .foregroundColor(.secondary)
            content
        }
    }
}

struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Binding var isPresented: Bool

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
                    CloseButton { isPresented = false }
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
        case .testDrive: return "🧪"
        case .ordered: return "📦"
        case .other: return "🔘"
        }
    }

    var fullDisplayName: String {
        switch self {
        case .new: return String.status_new_full
        case .contacted: return String.status_contacted_full
        case .demoScheduled: return String.status_demo_full
        case .testDrive: return String.status_test_drive_full
        case .ordered: return String.status_ordered_full
        case .other: return String.status_other_full
        }
    }

    var infoDescription: String {
        switch self {
        case .new: return String.status_new_desc
        case .contacted: return String.status_contacted_desc
        case .demoScheduled: return String.status_demo_desc
        case .testDrive: return String.status_test_drive_desc
        case .ordered: return String.status_ordered_desc
        case .other: return String.status_other_desc
        }
    }

    var nextAction: String {
        switch self {
        case .new: return String.status_new_action
        case .contacted: return String.status_contacted_action
        case .demoScheduled: return String.status_demo_action
        case .testDrive: return String.status_test_drive_action
        case .ordered: return String.status_ordered_action
        case .other: return String.status_other_action
        }
    }
}

extension SalonStatus {
    var displayName: String {
        switch self {
        case .new: return String.status_new
        case .contacted: return String.status_contacted
        case .demoScheduled: return String.status_demo
        case .testDrive: return String.status_test_drive
        case .ordered: return String.status_ordered
        case .other: return String.status_other
        }
    }

    var color: Color {
        switch self {
        case .new: return .green
        case .contacted: return .orange
        case .demoScheduled: return .blue
        case .testDrive: return .purple
        case .ordered: return .mint
        case .other: return .gray
        }
    }
}

#Preview {
    SalonListView()
}
