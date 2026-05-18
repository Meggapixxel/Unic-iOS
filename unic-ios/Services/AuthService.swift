import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Typed errors surfaced by `AuthService` for known Firebase authentication failure modes.
enum AuthError: LocalizedError {
    case userNotFound
    case wrongPassword
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .userNotFound:      return String(localized: "auth_error_user_not_found")
        case .wrongPassword:     return String(localized: "auth_error_wrong_password")
        case .unknown(let e):    return e.localizedDescription
        }
    }
}

/// Singleton service that manages Firebase Authentication state and exposes role-based permission checks.
///
/// On init it restores the last known `AppUser` from `UserDefaults` so views render immediately,
/// then patches it via a Firestore snapshot once Firebase confirms the auth state.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// The currently authenticated user, or `nil` if logged out.
    @Published private(set) var currentUser: AppUser?

    var isLoggedIn: Bool  { currentUser != nil }
    var isAdmin: Bool     { currentUser?.isAdmin ?? false }
    var isManager: Bool   { currentUser?.isManager ?? false }
    var isSales: Bool     { currentUser?.isSales ?? false }

    // MARK: - Permissions

    // Tabs
    var canViewSales:          Bool { isAdmin || isManager }
    var canViewUsers:          Bool { isAdmin }

    // Clients
    var canCreateClient:       Bool { isAdmin || isManager }
    var canEditClient:         Bool { isAdmin || isManager }
    var canDeleteClient:       Bool { isAdmin }

    // Invoices
    var canCreateInvoice:      Bool { isAdmin || isManager }
    var canEditInvoice:        Bool { isAdmin || isManager }
    var canDeleteInvoice:      Bool { isAdmin }

    // Salons
    var canEditSalon:          Bool { isAdmin || isManager }
    var canDeleteSalon:        Bool { isAdmin }
    var canEditStatusHistory:  Bool { isAdmin }
    var canDeleteStatusHistory: Bool { isAdmin }

    // Warehouse
    var canCreateStockMovement: Bool { canCreateInvoice }
    var canEditStockMovement:   Bool { isAdmin }

    // Activity / Test drives
    var canViewAllTestDrives:  Bool { isAdmin }
    var canDeleteActivity:     Bool { isAdmin }

    // Users
    var canViewAllUsers:       Bool { isAdmin }

    // Plans & Promos
    var canManagePlans:        Bool { isAdmin || isManager }
    var canManagePromos:       Bool { isAdmin || isManager }

    private let db = Firestore.firestore()
    private static let storageKey = "auth_current_user"

    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            do {
                currentUser = try JSONDecoder().decode(AppUser.self, from: data)
            } catch {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
        }
        observeAuthState()
    }

    private func observeAuthState() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { @MainActor in
                if let uid = firebaseUser?.uid {
                    try? await self.fetchAndStoreUser(uid: uid)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.storageKey)
                    self.currentUser = nil
                }
            }
        }
    }

    /// Signs in with email and password, fetches the user profile from Firestore, and updates `currentUser`.
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - password: The user's password.
    /// - Throws: `AuthError.userNotFound`, `AuthError.wrongPassword`, or `AuthError.unknown`.
    func login(email: String, password: String) async throws {
        AppLogger.log(.info, "Auth", "Login attempt: \(email)")
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let uid = result.user.uid
            try await fetchAndStoreUser(uid: uid)
            AppLogger.log(.info, "Auth", "Login success: uid=\(uid)")
        } catch let error as NSError {
            AppLogger.log(.error, "Auth", "Login failed (\(email)): \(error.localizedDescription)")
            switch AuthErrorCode(rawValue: error.code) {
            case .userNotFound, .invalidEmail, .invalidCredential:
                throw AuthError.userNotFound
            case .wrongPassword:
                throw AuthError.wrongPassword
            default:
                throw AuthError.unknown(error)
            }
        }
    }

    /// Signs out the current user, clears the cached profile from `UserDefaults`, and sets `currentUser` to `nil`.
    func logout() {
        AppLogger.log(.info, "Auth", "Logout: \(currentUser?.id ?? "unknown")")
        do {
            try Auth.auth().signOut()
        } catch {
            // Firebase signOut fails only for keychain issues; user session is cleared locally regardless
        }
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        currentUser = nil
    }

    /// Re-fetches the current user's Firestore profile and refreshes `currentUser`.
    /// - Returns: The refreshed `AppUser`, or the last cached value if Firebase is unavailable.
    func refreshCurrentUser() async -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return currentUser }
        AppLogger.log(.debug, "Auth", "Refreshing current user: uid=\(uid)")
        try? await fetchAndStoreUser(uid: uid)
        return currentUser
    }

    // MARK: - Private

    private func fetchAndStoreUser(uid: String) async throws {
        AppLogger.log(.debug, "Auth", "Fetching user profile: uid=\(uid)")
        let doc = try await db.collection("users").document(uid).getDocument()
        let data = doc.data() ?? [:]
        let firstName  = data["first_name"] as? String ?? ""
        let lastName   = data["last_name"]  as? String ?? ""
        let roleString = data["role"] as? String ?? ""
        let role       = UserRole(rawValue: roleString) ?? .sales

        let user = AppUser(id: uid, firstName: firstName, lastName: lastName, role: role)
        AppLogger.log(.debug, "Auth", "User loaded: \(firstName) \(lastName), role=\(roleString)")

        do {
            let encoded = try JSONEncoder().encode(user)
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        } catch {
            // JSONEncoder failure for a simple Codable struct is unexpected; session remains active
        }
        currentUser = user
    }

}
