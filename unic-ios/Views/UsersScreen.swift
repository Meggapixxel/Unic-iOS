import SwiftUI
import Combine

struct UsersScreen: View {
    @StateObject private var viewModel = UsersViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.visibleUsers) { user in
                    NavigationLink(destination: UserActivityScreen(user: user)) {
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton { dismiss() }
                }
            }
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
