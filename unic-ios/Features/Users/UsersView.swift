import ComposableArchitecture
import SwiftUI

struct UsersView: View {
    @Bindable var store: StoreOf<UsersFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                ForEach(store.users) { user in
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
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
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
        } destination: { store in
            switch store.case {
            case .userActivity(let store):
                UserActivityView(store: store)
            }
        }
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return .red
        case .manager: return .orange
        case .sales: return .blue
        }
    }
}
