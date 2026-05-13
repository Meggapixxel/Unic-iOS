import ComposableArchitecture
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    enum State: Equatable {
        case loading
        case auth(AuthFeature.State)
        case fetching(AppUser)
        case locationGate(AppUser)
        case main(MainFeature.State)
    }

    enum Action {
        case onAppear
        case authStateChanged(AppUser?)
        case fetchingCompleted(AppUser, needsLocation: Bool)
        case locationAuthorized(AppUser)
        case auth(AuthFeature.Action)
        case main(MainFeature.Action)
    }

    @Dependency(\.authClient) var auth
    @Dependency(\.firebaseClient) var firebase

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                return .run { send in
                    for await user in auth.observeAuthState() {
                        await send(.authStateChanged(user))
                    }
                }

            case .authStateChanged(let user):
                if let user {
                    if case .main = state { return .none }
                    state = .fetching(user)
                    return .run { send in
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await firebase.loadBundleCodes() }
                        }
                        let needsLocation = auth.isSales() && !LocationManager.shared.isAuthorized
                        if needsLocation {
                            LocationManager.shared.requestPermission()
                        }
                        await send(.fetchingCompleted(user, needsLocation: needsLocation))
                    }
                } else {
                    if case .auth = state { return .none }
                    state = .auth(AuthFeature.State())
                    return .none
                }

            case .fetchingCompleted(let user, let needsLocation):
                if needsLocation {
                    state = .locationGate(user)
                } else {
                    state = .main(MainFeature.State(currentUser: user))
                }
                return .none

            case .locationAuthorized(let user):
                state = .main(MainFeature.State(currentUser: user))
                return .none

            case .auth(.loginSucceeded):
                return .none

            case .auth, .main:
                return .none
            }
        }
        .ifCaseLet(\.auth, action: \.auth) { AuthFeature() }
        .ifCaseLet(\.main, action: \.main) { MainFeature() }
    }
}
