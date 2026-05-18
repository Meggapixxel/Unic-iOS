@preconcurrency import Combine
import ComposableArchitecture
import Foundation

/// TCA dependency that wraps `AuthService`, providing authentication actions and role-based
/// permission checks in a testable, injectable interface.
@DependencyClient
struct AuthClient: @unchecked Sendable {
    /// Authenticates the user with email and password.
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - password: The user's password.
    /// - Throws: An error from Firebase Auth when credentials are invalid or the network is unavailable.
    var login: @Sendable (_ email: String, _ password: String) async throws -> Void

    /// Signs the current user out and clears local session state.
    var logout: () -> Void

    /// Returns the currently authenticated `AppUser`, or `nil` if no session is active.
    var currentUser: () -> AppUser? = { nil }

    /// Re-fetches the current user's profile from Firestore and returns the updated value.
    var refreshCurrentUser: () async -> AppUser? = { nil }

    /// Emits `AppUser?` values whenever the Firebase Auth state changes; yields `nil` on sign-out.
    var observeAuthState: () -> AsyncStream<AppUser?> = { .finished }

    /// Whether the current user can access the Sales tab.
    var canViewSales: () -> Bool = { false }
    /// Whether the current user can access the Users management screen.
    var canViewUsers: () -> Bool = { false }
    /// Whether the current user can create or modify plans.
    var canManagePlans: () -> Bool = { false }
    /// Whether the current user can create or modify promotional offers.
    var canManagePromos: () -> Bool = { false }
    /// Whether the current user can create new FlexiBee invoices.
    var canCreateInvoice: () -> Bool = { false }
    /// Whether the current user can edit existing unpaid invoices.
    var canEditInvoice: () -> Bool = { false }
    /// Whether the current user can delete invoices.
    var canDeleteInvoice: () -> Bool = { false }
    /// Whether the current user can edit salon records.
    var canEditSalon: () -> Bool = { false }
    /// Whether the current user can delete salon records.
    var canDeleteSalon: () -> Bool = { false }
    /// Whether the current user can edit FlexiBee client records.
    var canEditClient: () -> Bool = { false }
    /// Whether the current user can delete FlexiBee client records.
    var canDeleteClient: () -> Bool = { false }
    /// Whether the current user can delete activity history entries.
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
    /// The registered `AuthClient` dependency, used by TCA reducers for auth and permission checks.
    nonisolated var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
