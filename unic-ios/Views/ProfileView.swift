import SwiftUI

struct ProfileView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var showLogoutConfirm = false
    @State private var showHistory = false

    var body: some View {
        List {
            if let user = auth.currentUser {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(roleColor(user.role).opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Text(initials(user))
                                    .font(.title3.bold())
                                    .foregroundStyle(roleColor(user.role))
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.fullName)
                                .font(.headline)
                            Text(user.role.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(String.profile_activity) {
                    Button {
                        showHistory = true
                    } label: {
                        Label(String.profile_activity_history, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
                .sheet(isPresented: $showHistory) {
                    NavigationStack {
                        UserActivityView(user: user)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    CloseButton { showHistory = false }
                                }
                            }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label(String.profile_logout, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle(String.profile_nav_title)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(String.profile_logout_confirm, isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(String.profile_logout, role: .destructive) { auth.logout() }
            Button(String.cancel, role: .cancel) {}
        }
    }

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

#Preview {
    ProfileView()
}
