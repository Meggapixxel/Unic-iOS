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
        case .userNotFound:      return String(localized: "auth_error_user_not_found")
        case .wrongPassword:     return String(localized: "auth_error_wrong_password")
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
        currentUser = nil
    }

    // MARK: - Private

    private func fetchAndStoreUser(uid: String) async throws {
        AppLogger.log(.info, "Auth", "Fetching user profile: uid=\(uid)")
        let doc = try await db.collection("users").document(uid).getDocument()
        let data = doc.data() ?? [:]
        let firstName  = data["first_name"] as? String ?? ""
        let lastName   = data["last_name"]  as? String ?? ""
        let roleString = data["role"] as? String ?? ""
        let role       = UserRole(rawValue: roleString) ?? .sales

        // Fetch current active plan from plans collection
        let currentPlan = try? await fetchActivePlan()

        // Read existing plan data from user doc
        let existingPlanData = data["activePlan"] as? [String: Any]
        let existingPlanId   = existingPlanData?["id"] as? String

        var userActivePlan: UserActivePlan?
        if let plan = currentPlan {
            userActivePlan = UserActivePlan(
                id: plan.id, title: plan.title,
                startDate: plan.startDate, endDate: plan.endDate,
                targetSalons: plan.targetSalons, targetSalonsPerDay: plan.targetSalonsPerDay,
                targetTestDrives: plan.targetTestDrives, targetTestDrivesPerDay: plan.targetTestDrivesPerDay,
                salonsVisited: 0, testDriveCount: 0
            )

            let planUpdate: [String: Any] = [
                "activePlan.id":                     plan.id ?? NSNull(),
                "activePlan.title":                  plan.title as Any,
                "activePlan.startDate":              Timestamp(date: plan.startDate),
                "activePlan.endDate":                Timestamp(date: plan.endDate),
                "activePlan.targetSalons":           plan.targetSalons as Any,
                "activePlan.targetSalonsPerDay":     plan.targetSalonsPerDay as Any,
                "activePlan.targetTestDrives":       plan.targetTestDrives as Any,
                "activePlan.targetTestDrivesPerDay": plan.targetTestDrivesPerDay as Any
            ]
            try? await db.collection("users").document(uid).updateData(planUpdate)

        } else if existingPlanData != nil {
            try? await db.collection("users").document(uid).updateData(["activePlan": FieldValue.delete()])
        }

        let user = AppUser(id: uid, firstName: firstName, lastName: lastName, role: role, activePlan: userActivePlan)
        AppLogger.log(.info, "Auth", "User loaded: \(firstName) \(lastName), role=\(roleString)")

        do {
            let encoded = try JSONEncoder().encode(user)
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        } catch {
            // JSONEncoder failure for a simple Codable struct is unexpected; session remains active
        }
        currentUser = user
    }

    private func fetchActivePlan() async throws -> Plan? {
        let now = Timestamp(date: Date())
        let snapshot = try await db.collection("plans")
            .whereField("endDate", isGreaterThanOrEqualTo: now)
            .order(by: "endDate")
            .limit(to: 5)
            .getDocuments()
        let plans = snapshot.documents.compactMap { try? $0.data(as: Plan.self) }
        return plans.first { $0.isActive }
    }
}
