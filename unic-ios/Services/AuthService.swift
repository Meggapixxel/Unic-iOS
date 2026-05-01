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

    private let db = Firestore.firestore()
    private static let storageKey = "auth_current_user"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
        }
    }

    func login(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let uid = result.user.uid
            try await fetchAndStoreUser(uid: uid)
        } catch let error as NSError {
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
        try? Auth.auth().signOut()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        currentUser = nil
    }

    // MARK: - Private

    private func fetchAndStoreUser(uid: String) async throws {
        let doc = try await db.collection("users").document(uid).getDocument()
        let data = doc.data() ?? [:]
        let firstName = data["first_name"] as? String ?? ""
        let lastName  = data["last_name"]  as? String ?? ""
        let roleString = data["role"] as? String ?? ""
        let role = UserRole(rawValue: roleString) ?? .sales
        let user = AppUser(id: uid, firstName: firstName, lastName: lastName, role: role)

        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
        currentUser = user
    }
}
