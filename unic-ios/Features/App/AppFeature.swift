import ComposableArchitecture
import Foundation

/// Root TCA reducer that manages the top-level application lifecycle, switching between loading, authentication,
/// welcome (preload), and main tab-bar states based on Firebase auth events.
///
/// **Entry point**
/// `AppView` dispatches `.onAppear` once, which opens a long-lived `AsyncStream` via `authClient.observeAuthState()`.
/// Every emission from that stream fires `.authStateChanged(_:)`, driving all subsequent state transitions.
///
/// **Key action flows**
/// - `.onAppear` — Starts the `observeAuthState()` stream as a long-running `Effect.run`. The effect never
///   cancels for the lifetime of the app, so auth changes (sign-in, sign-out, token refresh) are always handled.
/// - `.authStateChanged(nil)` — User is signed out (or no session on cold launch). Transitions to `.auth` unless
///   already there, preventing redundant resets.
/// - `.authStateChanged(user)` — User is authenticated. If already in `.main`, updates `currentUser` and
///   `profile.currentUser` in place (handles silent token refreshes without navigating away). If in any other
///   state, transitions to `.welcome` to begin the preload phase.
/// - `.welcome(.delegate(.readyToEnter(user, salons)))` — `WelcomeFeature` has finished preloading; the app
///   transitions to `.main`, passing the preloaded salons to avoid a second Firebase round-trip.
///
/// **Navigation / state machine**
/// ```
/// .loading ──(first auth event)──► .auth
///                                  .welcome ──(readyToEnter)──► .main
///         ──(user present)──────── .welcome
/// .main   ──(sign-out)──────────── .auth
/// ```
/// There is no `Path` or `Destination`; navigation is expressed as enum-case replacement on `State`.
///
/// **Side effects**
/// - `authClient.observeAuthState()` — continuous Firebase Auth listener (never cancelled).
/// - No direct Firebase data fetching; data loading is delegated to `WelcomeFeature`.
@Reducer
struct AppFeature {

    /// The current phase of the application lifecycle.
    @ObservableState
    enum State: Equatable {
        /// Initial state while the auth session is being determined.
        case loading
        /// The user is unauthenticated and must log in.
        case auth(AuthFeature.State)
        /// The user is authenticated and the app is preloading data before entering.
        case welcome(WelcomeFeature.State)
        /// The user is fully authenticated and the main tab interface is active.
        case main(MainFeature.State)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case let (.auth(l), .auth(r)): return l == r
            case let (.welcome(l), .welcome(r)): return l == r
            case let (.main(l), .main(r)): return l == r
            default: return false
            }
        }
    }

    /// Actions that drive top-level app state transitions.
    enum Action {
        /// Triggers the auth-state observation stream on first appearance.
        case onAppear
        /// Fired whenever Firebase auth emits a new user value (nil means signed out).
        case authStateChanged(AppUser?)
        case auth(AuthFeature.Action)
        case welcome(WelcomeFeature.Action)
        case main(MainFeature.Action)
    }

    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let authClient = auth
                return .run { send in
                    let stream = await MainActor.run { authClient.observeAuthState() }
                    for await user in stream {
                        await send(.authStateChanged(user))
                    }
                }

            case .authStateChanged(let user):
                if let user {
                    switch state {
                    case .main(var mainState):
                        mainState.currentUser = user
                        mainState.profile.currentUser = user
                        state = .main(mainState)
                    case .welcome:
                        break
                    default:
                        state = .welcome(WelcomeFeature.State(user: user))
                    }
                } else {
                    guard case .auth = state else {
                        state = .auth(AuthFeature.State())
                        return .none
                    }
                }
                return .none

            case .welcome(.delegate(.readyToEnter(let user, let salons))):
                state = .main(MainFeature.State(currentUser: user, preloadedSalons: salons))
                return .none

            case .auth, .welcome, .main:
                return .none
            }
        }
        .ifCaseLet(\.auth, action: \.auth) { AuthFeature() }
        .ifCaseLet(\.welcome, action: \.welcome) { WelcomeFeature() }
        .ifCaseLet(\.main, action: \.main) { MainFeature() }
    }
}
