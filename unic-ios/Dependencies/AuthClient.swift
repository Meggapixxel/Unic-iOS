import ComposableArchitecture
import Foundation

@DependencyClient
struct AuthClient {
    var login: (_ email: String, _ password: String) async throws -> Void
    var logout: () -> Void
    var currentUser: () -> AppUser? = { nil }
    var observeAuthState: () -> AsyncStream<AppUser?> = { .finished }
    var canViewSales: () -> Bool = { false }
    var canViewUsers: () -> Bool = { false }
    var canManagePlans: () -> Bool = { false }
    var canManagePromos: () -> Bool = { false }
    var canCreateInvoice: () -> Bool = { false }
    var canEditInvoice: () -> Bool = { false }
    var canDeleteInvoice: () -> Bool = { false }
    var canEditSalon: () -> Bool = { false }
    var canDeleteSalon: () -> Bool = { false }
    var canDeleteClient: () -> Bool = { false }
    var canDeleteActivity: () -> Bool = { false }
    var isAdmin: () -> Bool = { false }
    var isManager: () -> Bool = { false }
    var isSales: () -> Bool = { false }
}

extension AuthClient: DependencyKey {
    static var liveValue: Self {
        let service = AuthService.shared
        return Self(
            login: { email, password in try await service.login(email: email, password: password) },
            logout: { service.logout() },
            currentUser: { service.currentUser },
            observeAuthState: {
                AsyncStream { continuation in
                    // Use NotificationCenter or Timer-based polling since AuthService uses @Published
                    let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        continuation.yield(service.currentUser)
                    }
                    continuation.onTermination = { _ in timer.invalidate() }
                }
            },
            canViewSales: { service.canViewSales },
            canViewUsers: { service.canViewUsers },
            canManagePlans: { service.canManagePlans },
            canManagePromos: { service.canManagePromos },
            canCreateInvoice: { service.canCreateInvoice },
            canEditInvoice: { service.canEditInvoice },
            canDeleteInvoice: { service.canDeleteInvoice },
            canEditSalon: { service.canEditSalon },
            canDeleteSalon: { service.canDeleteSalon },
            canDeleteClient: { service.canDeleteClient },
            canDeleteActivity: { service.canDeleteActivity },
            isAdmin: { service.isAdmin },
            isManager: { service.isManager },
            isSales: { service.isSales }
        )
    }
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
