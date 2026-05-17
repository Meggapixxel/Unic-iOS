import Foundation

enum AppDestination: Hashable {
    case product(FlexiBeeStockItem)
    case invoice(FlexiBeeInvoice)
    case allTopProducts
    case allTopClients
    case userActivity(AppUser)
    case stockChecklist
    case plans
    case sales
    case users
}
