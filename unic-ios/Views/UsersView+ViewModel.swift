import SwiftUI
import Combine

/// Loads and displays the team member list. Only admins can see other admin accounts —
/// non-admin roles receive a filtered list via `visibleUsers`.
@MainActor
final class UsersViewModel: ObservableObject {
    @Published private var users: [AppUser] = []
    @Published var isLoading = false
    @Published var error: String?

    private let service = FirebaseService.shared
    private let auth    = AuthService.shared

    /// Hides admin accounts from non-admin users to prevent role enumeration.
    var visibleUsers: [AppUser] {
        auth.canViewAllUsers
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
        error = nil
        do {
            users = try await service.fetchAllUsers()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
