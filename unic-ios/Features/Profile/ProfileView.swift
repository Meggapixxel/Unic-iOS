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

                // MARK: Activity
                Section(String.profile_activity) {
                    Button {
                        store.send(.navigateToActivity)
                    } label: {
                        Label(String.profile_activity_history, systemImage: "clock.arrow.circlepath")
                            .foregroundColor(.primary)
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

                // MARK: Plans (conditional)
                if store.canManagePlans {
                    Section {
                        Button {
                            store.send(.navigateToPlans)
                        } label: {
                            Label(String.plans_nav_title, systemImage: "target")
                                .foregroundColor(.primary)
                        }
                    }
                }

                // MARK: Logout
                Section {
                    Button(role: .destructive) {
                        store.send(.logoutTapped)
                    } label: {
                        Label(String.profile_logout, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(String.profile_nav_title)
            .navigationBarTitleDisplayMode(.large)
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
            switch pathStore.case {
            case let .userActivity(activityStore):
                UserActivityView(store: activityStore)

            case let .sales(salesStore):
                SalesView(store: salesStore)

            case let .users(usersStore):
                UsersView(store: usersStore)

            case let .plans(plansStore):
                PlansView(store: plansStore)
            }
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

// MARK: - TCA Bridge Views for TestDrive and RoutePlanner in SalonsFeature path
// These wrap the legacy views for use in the NavigationStack destination.

struct TestDriveView: View {
    let store: StoreOf<TestDriveFeature>

    var body: some View {
        TestDriveScreen(
            salons: Array(store.salons),
            onSalonUpdated: { _ in },
            onSalonDeleted: { _ in }
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
