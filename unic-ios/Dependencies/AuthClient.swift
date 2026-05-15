@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@DependencyClient
struct AuthClient: @unchecked Sendable {
    var login: @Sendable (_ email: String, _ password: String) async throws -> Void
    var logout: () -> Void
    var currentUser: () -> AppUser? = { nil }
    var refreshCurrentUser: () async -> AppUser? = { nil }
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
    var canEditClient: () -> Bool = { false }
    var canDeleteClient: () -> Bool = { false }
    var canDeleteActivity: () -> Bool = { false }
    var isAdmin: () -> Bool = { false }
    var isManager: () -> Bool = { false }
    var isSales: () -> Bool = { false }
}

extension AuthClient: DependencyKey {
    static var liveValue: Self {
        MainActor.assumeIsolated {
            let service = AuthService.shared
            return Self(
                login: { email, password in try await service.login(email: email, password: password) },
                logout: { MainActor.assumeIsolated { service.logout() } },
                currentUser: { MainActor.assumeIsolated { service.currentUser } },
                refreshCurrentUser: { await service.refreshCurrentUser() },
                observeAuthState: {
                    MainActor.assumeIsolated {
                        AsyncStream { continuation in
                            let cancellable = service.$currentUser.sink { user in
                                continuation.yield(user)
                            }
                            continuation.onTermination = { _ in cancellable.cancel() }
                        }
                    }
                },
                canViewSales: { MainActor.assumeIsolated { service.canViewSales } },
                canViewUsers: { MainActor.assumeIsolated { service.canViewUsers } },
                canManagePlans: { MainActor.assumeIsolated { service.canManagePlans } },
                canManagePromos: { MainActor.assumeIsolated { service.canManagePromos } },
                canCreateInvoice: { MainActor.assumeIsolated { service.canCreateInvoice } },
                canEditInvoice: { MainActor.assumeIsolated { service.canEditInvoice } },
                canDeleteInvoice: { MainActor.assumeIsolated { service.canDeleteInvoice } },
                canEditSalon: { MainActor.assumeIsolated { service.canEditSalon } },
                canDeleteSalon: { MainActor.assumeIsolated { service.canDeleteSalon } },
                canEditClient: { MainActor.assumeIsolated { service.canEditClient } },
                canDeleteClient: { MainActor.assumeIsolated { service.canDeleteClient } },
                canDeleteActivity: { MainActor.assumeIsolated { service.canDeleteActivity } },
                isAdmin: { MainActor.assumeIsolated { service.isAdmin } },
                isManager: { MainActor.assumeIsolated { service.isManager } },
                isSales: { MainActor.assumeIsolated { service.isSales } }
            )
        }
    }
}

extension DependencyValues {
    nonisolated var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
