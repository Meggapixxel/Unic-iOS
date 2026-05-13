import Foundation

enum AppDestination: Hashable {
    case product(FlexiBeeStockWithPrice)
    case invoice(FlexiBeeInvoice)
    case allTopProducts
    case allTopClients
    case userActivity(AppUser)
    case stockChecklist
}
