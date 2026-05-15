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
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }

                // MARK: Progress
                Section(String.profile_plans_progress) {
                    if let plan = store.currentUser.activePlan, plan.isActive {
                        VStack(alignment: .leading, spacing: 10) {
                            if let title = plan.title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack(spacing: 24) {
                                if let target = plan.targetSalons, target > 0 {
                                    RingProgressView(
                                        value: plan.salonsVisited,
                                        target: target,
                                        label: String.plan_target_salons,
                                        color: .blue
                                    )
                                }
                                if let target = plan.targetTestDrives, target > 0 {
                                    RingProgressView(
                                        value: plan.testDriveCount,
                                        target: target,
                                        label: String.plan_target_test_drives,
                                        color: .green
                                    )
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                    Button {
                        store.send(.navigateToActivity)
                    } label: {
                        Label(String.profile_activity_history, systemImage: "clock.arrow.circlepath")
                            .foregroundColor(.primary)
                    }
                    if store.canManagePlans {
                        Button {
                            store.send(.navigateToPlans)
                        } label: {
                            Label(String.plans_nav_title, systemImage: "target")
                                .foregroundColor(.primary)
                        }
                    }
                }

                // MARK: Sales (conditional)
                if store.canViewSales {
                    Section {
                        Button {
                            store.send(.navigateToSales)
                        } label: {
                            Label(String.sales_nav_title, systemImage: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.primary)
                        }
                    }
                }

                // MARK: Users (conditional)
                if store.canViewUsers {
                    Section {
                        Button {
                            store.send(.navigateToUsers)
                        } label: {
                            Label(String.users_nav_title, systemImage: "person.2.fill")
                                .foregroundColor(.primary)
                        }
                    }
                }

            }
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
