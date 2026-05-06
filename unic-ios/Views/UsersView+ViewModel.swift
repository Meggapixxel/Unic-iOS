import SwiftUI
import Combine

@MainActor
final class UsersViewModel: ObservableObject {
    @Published private var users: [AppUser] = []
    @Published var isLoading = false

    private let service = FirebaseService.shared
    private let auth    = AuthService.shared

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
        users = (try? await service.fetchAllUsers()) ?? []
        isLoading = false
    }
}
