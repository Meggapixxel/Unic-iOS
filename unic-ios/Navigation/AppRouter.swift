import SwiftUI

/// Observable navigation controller that owns the `NavigationPath` for the app's root `NavigationStack`.
///
/// Inject a single `AppRouter` instance into the environment and call its methods from views or
/// view models to drive programmatic navigation without coupling screens together.
@Observable
final class AppRouter {
    /// The current navigation stack, bound directly to a `NavigationStack`.
    var path = NavigationPath()

    /// Pushes `destination` onto the navigation stack.
    /// - Parameter destination: The screen to navigate to.
    func push(_ destination: AppDestination) {
        path.append(destination)
    }

    /// Pops the top-most screen from the stack. No-ops when the stack is already empty.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Pops all screens, returning to the root of the navigation stack.
    func popToRoot() {
        path.removeLast(path.count)
    }
}
