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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Content: List or Map
                if viewModel.isLoading {
                    ProgressView("Завантаження...")
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
                            SalonDetailView(salon: salon) { updatedSalon in
                                viewModel.updateSalon(updatedSalon)
                            }
                        } label: {
                            SalonRowView(salon: salon)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.loadSalons()
                    }
                    .searchable(text: $viewModel.searchText, prompt: "Пошук салонів...")
                    .safeAreaInset(edge: .bottom) {
                        VStack {
                            // Stats Header
                            StatsHeaderView(viewModel: viewModel)
                                .padding(.horizontal)

                            // Filter Chips
                            FilterChipsView(statusOptions: $viewModel.statusOptions)
                        }
                        .padding(.vertical)
                        .glassBackgroundRectangle(cornerRadius: 20)
                        .padding(.horizontal)
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
                                }
                                .popover(isPresented: $viewModel.showFilterPopover) {
                                    TypeFilterPopoverView(viewModel: viewModel)
                                        .presentationCompactAdaptation(.popover)
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation {
                                viewModel.showMap.toggle()
                            }
                        } label: {
                            Image(systemName: viewModel.showMap ? "list.bullet" : "map")
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
        }
    }
}

// MARK: - Stats Header

struct StatsHeaderView: View {
    @ObservedObject var viewModel: SalonsViewModel

    var body: some View {
        HStack(spacing: 16) {
            StatBadge(title: "Всього", value: viewModel.totalCount, color: .blue)
            StatBadge(title: "Нові", value: viewModel.newCount, color: .green)
            StatBadge(title: "В роботі", value: viewModel.contactedCount, color: .orange)
            StatBadge(title: "Замовили", value: viewModel.orderedCount, color: .purple)
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Всі", isSelected: !statusOptions.hasSelection) {
                    statusOptions.clear()
                }

                ForEach(statusOptions.all) { status in
                    FilterChip(
                        title: status.displayName,
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
                Text("Сортування")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Тип закладу")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.typeOptions.hasSelection {
                    Button("Скинути") {
                        viewModel.typeOptions.clear()
                    }
                    .font(.caption)
                }
            }

            if viewModel.typeOptions.all.isEmpty {
                Text("Немає даних")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
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
        }
        .padding(20)
        .frame(width: 220)
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
            
            Button("Спробувати знову", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Extensions

extension SalonStatus {
    var displayName: String {
        switch self {
        case .new: return "Новий"
        case .contacted: return "Контакт"
        case .demoScheduled: return "Демо"
        case .testing: return "Тест"
        case .ordered: return "Замовив"
        case .lost: return "Втрачено"
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
