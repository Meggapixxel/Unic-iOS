import ComposableArchitecture
import SwiftUI

/// List view showing all visible app users with role-coloured avatars; tapping a user opens their activity log.
struct UsersView: View {
    @Bindable var store: StoreOf<UsersFeature>

    var body: some View {
        List {
            ForEach(store.users) { user in
                userRow(user)
            }
        }
        .listStyle(.plain)
        .navigationTitle(String.users_nav_title)
        .overlay {
            if store.isLoading { ProgressView() }
            else if store.users.isEmpty {
                ContentUnavailableView(String.users_empty, systemImage: "person.2")
            }
        }
        .task { store.send(.onLoad) }
    }

    /// Builds a tappable row for a single user with an initials avatar and role label.
    /// - Parameter user: The user to display.
    /// - Returns: A `Button` styled row view.
    private func userRow(_ user: AppUser) -> some View {
        Button { store.send(.userTapped(user)) } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(roleColor(user.role).opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                            .font(.subheadline.bold())
                            .foregroundStyle(roleColor(user.role))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName).font(.callout)
                    Text(user.role.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Maps a user role to its representative accent colour.
    /// - Parameter role: The role to look up.
    /// - Returns: A `Color` used for the avatar background and icon tint.
    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return .red
        case .manager: return .orange
        case .sales: return .blue
        }
    }
}
