import Foundation

/// All type-safe destinations that can be pushed onto the app's shared `NavigationPath`.
///
/// Each case corresponds to a distinct screen reachable via `AppRouter.push(_:)`.
enum AppDestination: Hashable {
    /// Detail screen for a specific stock item.
    case product(FlexiBeeStockItem)
    /// Detail screen for a specific FlexiBee invoice.
    case invoice(FlexiBeeInvoice)
    /// Full list of top-selling products.
    case allTopProducts
    /// Full list of top clients by revenue.
    case allTopClients
    /// Activity timeline for the given sales user.
    case userActivity(AppUser)
    /// Stock checklist screen.
    case stockChecklist
    /// Plan management screen.
    case plans
    /// Sales dashboard screen.
    case sales
    /// User management screen.
    case users
}
