import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

enum AuthError: LocalizedError {
    case userNotFound
    case wrongPassword
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .userNotFound:      return String.auth_error_user_not_found
        case .wrongPassword:     return String.auth_error_wrong_password
        case .unknown(let e):    return e.localizedDescription
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: AppUser?

    var isLoggedIn: Bool  { currentUser != nil }
    var isAdmin: Bool     { currentUser?.isAdmin ?? false }
    var isManager: Bool   { currentUser?.isManager ?? false }
    var isSales: Bool     { currentUser?.isSales ?? false }

    // MARK: - Permissions

    // Tabs
    var canViewAnalytics:      Bool { isAdmin || isManager }
    var canViewInvoices:       Bool { isAdmin || isManager }
    var canViewUsers:          Bool { isAdmin }

    // Clients
    var canCreateClient:       Bool { isAdmin || isManager }
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

    private let db = Firestore.firestore()
    private static let storageKey    = "auth_current_user"
    private static let cacheAgeKey   = "auth_cache_date"
    private static let cacheTTL: TimeInterval = 7 * 24 * 3600 // 1 week

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            do {
                currentUser = try JSONDecoder().decode(AppUser.self, from: data)
            } catch {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
                UserDefaults.standard.removeObject(forKey: Self.cacheAgeKey)
            }
        }
        observeAuthState()
    }

    private var isCacheStale: Bool {
        guard let saved = UserDefaults.standard.object(forKey: Self.cacheAgeKey) as? Date else { return true }
        return Date().timeIntervalSince(saved) > Self.cacheTTL
    }

    private func observeAuthState() {
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { @MainActor in
                if let uid = firebaseUser?.uid {
                    let needsRefresh = self.currentUser?.id != uid
                                   || self.currentUser == nil
                                   || self.isCacheStale
                    if needsRefresh {
                        try? await self.fetchAndStoreUser(uid: uid)
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.storageKey)
                    UserDefaults.standard.removeObject(forKey: Self.cacheAgeKey)
                    self.currentUser = nil
                }
            }
        }
    }

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

    func logout() {
        AppLogger.log(.info, "Auth", "Logout: \(currentUser?.id ?? "unknown")")
        do {
            try Auth.auth().signOut()
        } catch {
            // Firebase signOut fails only for keychain issues; user session is cleared locally regardless
        }
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheAgeKey)
        currentUser = nil
    }

    // MARK: - Private

    private func fetchAndStoreUser(uid: String) async throws {
        AppLogger.log(.info, "Auth", "Fetching user profile: uid=\(uid)")
        let doc = try await db.collection("users").document(uid).getDocument()
        let data = doc.data() ?? [:]
        let firstName = data["first_name"] as? String ?? ""
        let lastName  = data["last_name"]  as? String ?? ""
        let roleString = data["role"] as? String ?? ""
        let role = UserRole(rawValue: roleString) ?? .sales
        let user = AppUser(id: uid, firstName: firstName, lastName: lastName, role: role)
        AppLogger.log(.info, "Auth", "User loaded: \(firstName) \(lastName), role=\(roleString)")

        do {
            let encoded = try JSONEncoder().encode(user)
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
            UserDefaults.standard.set(Date(), forKey: Self.cacheAgeKey)
        } catch {
            // JSONEncoder failure for a simple Codable struct is unexpected; session remains active
        }
        currentUser = user
    }
}
