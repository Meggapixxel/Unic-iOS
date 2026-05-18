// FILE: unic-ios/Features/Profile/ProfileView.swift

import ComposableArchitecture
import SwiftUI

/// Profile tab root view displaying user info, in-plan KPI rings, plan history, and navigation rows.
struct ProfileView: View {
    @Bindable var store: StoreOf<ProfileFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                // MARK: User Card
                Section {
                    HStack(spacing: 14) {
                        AvatarCircle(
                            text: initials(store.currentUser),
                            color: roleColor(store.currentUser.role),
                            size: 56
                        )
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
                if store.activePlan != nil {
                    Section {
                        if let plan = store.activePlan {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Text(planPeriodString(from: plan.startDate, to: plan.endDate))
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

                                Group {
                                    if store.isLoadingActivity {
                                        HStack {
                                            ProgressView()
                                            Spacer()
                                        }
                                        .frame(height: 80)
                                    } else {
                                        let hasPlanRings = (plan.targetSalons ?? 0) > 0 || (plan.targetTestDrives ?? 0) > 0
                                        let hasDayRings = plan.isActive && (plan.targetSalonsPerDay > 0 || plan.targetTestDrivesPerDay > 0)

                                        VStack(alignment: .leading, spacing: 14) {
                                            if hasPlanRings {
                                                Text(String.plan_goal_total)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                HStack(spacing: 40) {
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
                                                }
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            }

                                            if hasDayRings {
                                                Text(String.activity_today)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                HStack(spacing: 40) {
                                                    if plan.targetSalonsPerDay > 0 {
                                                        RingProgressView(
                                                            value: store.salonsToday,
                                                            target: plan.targetSalonsPerDay,
                                                            label: String.plan_target_salons,
                                                            color: .blue
                                                        )
                                                    }
                                                    if plan.targetTestDrivesPerDay > 0 {
                                                        RingProgressView(
                                                            value: store.testDrivesToday,
                                                            target: plan.targetTestDrivesPerDay,
                                                            label: String.plan_target_test_drives,
                                                            color: .green
                                                        )
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            }
                                        }
                                    }
                                }
                                .animation(.easeInOut(duration: 0.35), value: store.isLoadingActivity)

                                if store.newClientsInPlan > 0 || store.returningClientsInPlan > 0 {
                                    HStack(spacing: 20) {
                                        StatBadge(
                                            title: String.stat_new_clients,
                                            value: store.newClientsInPlan,
                                            color: plan.isPast ? .secondary : .orange
                                        )
                                        StatBadge(
                                            title: String.stat_returning_clients,
                                            value: store.returningClientsInPlan,
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
            .navigationInlineTitle(String.profile_nav_title)
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

    /// Returns the two-letter uppercase initials derived from a user's first and last name.
    /// - Parameter user: The user whose initials are needed.
    /// - Returns: A string of up to two uppercase characters.
    private func initials(_ user: AppUser) -> String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    /// Maps a user role to its representative accent color.
    /// - Parameter role: The role to convert.
    /// - Returns: A `Color` used for avatars and highlights.
    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin:   return .red
        case .manager: return .orange
        case .sales:   return .blue
        }
    }
}

// MARK: - Ring Progress View

/// Circular progress ring displaying a numeric value against a target, with a label beneath.
struct RingProgressView: View {
    /// Achieved count to display inside the ring.
    let value: Int
    /// Goal count; the ring fills proportionally.
    let target: Int
    /// Short label shown below the ring.
    let label: String
    let color: Color

    /// Fractional progress clamped to `[0, 1]`.
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

/// Compact inline stat display showing a bold count above a descriptive caption label.
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

/// Single row in the plan-history list showing the period dates and achieved vs. target numbers.
struct PlanHistoryRowView: View {
    let entry: UserPlanHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(planPeriodString(from: entry.startDate, to: entry.endDate))
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

/// TCA-compatible bridge that wraps the legacy `TestDriveScreen` for use inside a `NavigationStack` destination.
struct TestDriveView: View {
    let store: StoreOf<TestDriveFeature>

    var body: some View {
        TestDriveScreen(
            salons: Array(store.salons),
            onSalonTapped: { store.send(.salonTapped($0)) }
        )
    }
}

/// TCA-compatible bridge that wraps the legacy `RoutePlannerScreen` for use as a fullScreenCover.
struct RoutePlannerView: View {
    let store: StoreOf<RoutePlannerFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoutePlannerScreen(
            salons: store.salons,
            isPresented: Binding(get: { true }, set: { if !$0 { dismiss() } })
        )
    }
}
