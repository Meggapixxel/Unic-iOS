// FILE: unic-ios/Features/Profile/ProfileView.swift

import ComposableArchitecture
import SwiftUI

struct ProfileView: View {
    @Bindable var store: StoreOf<ProfileFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                // MARK: User Card
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(roleColor(store.currentUser.role).opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Text(initials(store.currentUser))
                                    .font(.title3.bold())
                                    .foregroundStyle(roleColor(store.currentUser.role))
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.currentUser.fullName)
                                .font(.headline)
                            Text(store.currentUser.role.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                // MARK: Progress
                if store.currentUser.activePlan != nil {
                    Section {
                        if let plan = store.currentUser.activePlan {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Text("\(plan.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(plan.endDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                                        .font(.subheadline.weight(.semibold))
                                    if plan.isPast {
                                        Text(String.plan_ended)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(String.see_all) {
                                        store.send(.navigateToActivity)
                                    }
                                    .font(.subheadline)
                                }

                                HStack(spacing: 28) {
                                    if let target = plan.targetSalons, target > 0 {
                                        RingProgressView(
                                            value: store.salonsInPlan,
                                            target: target,
                                            label: String.plan_target_salons,
                                            color: plan.isPast ? .secondary : .blue
                                        )
                                    }
                                    if let target = plan.targetTestDrives, target > 0 {
                                        RingProgressView(
                                            value: store.testDrivesInPlan,
                                            target: target,
                                            label: String.plan_target_test_drives,
                                            color: plan.isPast ? .secondary : .green
                                        )
                                    }
                                    Spacer()
                                }

                                if store.newClientsInPlan > 0 || store.returningClientsInPlan > 0 {
                                    HStack(spacing: 20) {
                                        ClientStatChip(
                                            count: store.newClientsInPlan,
                                            label: String.stat_new_clients,
                                            color: plan.isPast ? .secondary : .orange
                                        )
                                        ClientStatChip(
                                            count: store.returningClientsInPlan,
                                            label: String.stat_returning_clients,
                                            color: plan.isPast ? .secondary : .purple
                                        )
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: Plan History
                if !store.planHistory.isEmpty {
                    Section(String.plan_history) {
                        ForEach(store.planHistory) { entry in
                            PlanHistoryRowView(entry: entry)
                        }
                    }
                }

                // MARK: Navigation rows
                if store.canViewSales || store.canViewUsers {
                    Section {
                        if store.canViewSales {
                            Button {
                                store.send(.navigateToSales)
                            } label: {
                                Label(String.sales_nav_title, systemImage: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(.primary)
                            }
                            Button {
                                store.send(.navigateToClients)
                            } label: {
                                Label(String.stat_clients, systemImage: "person.crop.rectangle.stack")
                                    .foregroundStyle(.primary)
                            }
                        }
                        if store.canViewUsers {
                            Button {
                                store.send(.navigateToUsers)
                            } label: {
                                Label(String.users_nav_title, systemImage: "person.2.fill")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String.profile_nav_title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.send(.logoutTapped)
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .tint(.red)
                }
            }
            .task { store.send(.onLoad) }
            .refreshable { await store.send(.onLoad).finish() }
            .confirmationDialog(
                String.profile_logout_confirm,
                isPresented: $store.showLogoutConfirm,
                titleVisibility: .visible
            ) {
                Button(String.profile_logout, role: .destructive) {
                    store.send(.logoutConfirmed)
                }
                Button(String.cancel, role: .cancel) { }
            }
        } destination: { pathStore in
            Group {
                switch pathStore.case {
                case let .userActivity(activityStore):
                    UserActivityView(store: activityStore)
                case let .sales(salesStore):
                    SalesView(store: salesStore)
                case let .invoiceDetail(detailStore):
                    InvoiceDetailView(store: detailStore)
                case let .allTopClients(clientsStore):
                    AllTopClientsView(store: clientsStore)
                case let .allTopProducts(productsStore):
                    AllTopProductsView(store: productsStore)
                case let .users(usersStore):
                    UsersView(store: usersStore)
                case let .plans(plansStore):
                    PlansView(store: plansStore)
                case let .productDetail(productStore):
                    ProductDetailView(store: productStore)
                case let .clientDetail(clientStore):
                    ClientDetailView(store: clientStore)
                }
            }
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Helpers

    private func initials(_ user: AppUser) -> String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin:   return .red
        case .manager: return .orange
        case .sales:   return .blue
        }
    }
}

// MARK: - Ring Progress View

struct RingProgressView: View {
    let value: Int
    let target: Int
    let label: String
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(value) / Double(target), 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)
                VStack(spacing: 1) {
                    Text("\(value)")
                        .font(.title3.bold())
                        .foregroundStyle(color)
                    Text("/\(target)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Client Stat Chip

struct ClientStatChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Plan History Row

struct PlanHistoryRowView: View {
    let entry: UserPlanHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(entry.endDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                if let target = entry.targetSalons, target > 0 {
                    Label("\(entry.result.salons)/\(target)", systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let target = entry.targetTestDrives, target > 0 {
                    Label("\(entry.result.testDrives)/\(target)", systemImage: "car")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}


// MARK: - TCA Bridge Views for TestDrive and RoutePlanner in SalonsFeature path
// These wrap the legacy views for use in the NavigationStack destination.

struct TestDriveView: View {
    let store: StoreOf<TestDriveFeature>

    var body: some View {
        TestDriveScreen(
            salons: Array(store.salons),
            onSalonTapped: { store.send(.salonTapped($0)) }
        )
    }
}

struct RoutePlannerView: View {
    let store: StoreOf<RoutePlannerFeature>

    var body: some View {
        RoutePlannerScreen(
            salons: store.salons,
            isPresented: .constant(true)
        )
    }
}
