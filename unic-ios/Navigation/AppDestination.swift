import Foundation

enum AppDestination: Hashable {
    case product(FlexiBeeStockWithPrice)
    case invoice(FlexiBeeInvoice)
    case invoiceWithMovement(FlexiBeeInvoice)
    case allTopProducts
    case allTopClients
}
