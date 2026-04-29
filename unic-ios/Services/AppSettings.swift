import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let userKey = "app_current_user"

    @Published var currentUser: String {
        didSet { UserDefaults.standard.set(currentUser, forKey: Self.userKey) }
    }

    private init() {
        currentUser = UserDefaults.standard.string(forKey: Self.userKey) ?? "admin"
    }

    var isAdmin: Bool { currentUser.lowercased() == "admin" }
}
