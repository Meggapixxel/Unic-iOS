import SwiftUI
import Combine

@MainActor
final class UsersViewModel: ObservableObject {
    @Published private var users: [AppUser] = []
    @Published var isLoading = false

    private let service = FirebaseService.shared
    private let auth    = AuthService.shared

    var visibleUsers: [AppUser] {
        auth.isAdmin
            ? users
            : users.filter { $0.role != .admin }
    }

    func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin:   return .red
        case .manager: return .blue
        case .sales:   return .green
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        users = (try? await service.fetchAllUsers()) ?? []
        isLoading = false
    }
}

struct UsersView: View {
    @StateObject private var viewModel = UsersViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.visibleUsers) { user in
                    NavigationLink(destination: UserActivityView(user: user)) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(viewModel.roleColor(user.role).opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(viewModel.roleColor(user.role))
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.fullName)
                                    .font(.callout)
                                Text(user.role.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(String.users_nav_title)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .overlay {
                if !viewModel.isLoading && viewModel.visibleUsers.isEmpty {
                    ContentUnavailableView(String.users_empty, systemImage: "person.2")
                }
            }
            .task { await viewModel.load() }
        }
    }
}
