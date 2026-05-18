import SwiftUI

/// UI-layer extensions on `PaymentStatus`.
extension PaymentStatus {
    /// SwiftUI color that represents the payment status at a glance.
    var color: Color {
        switch self {
        case .paid:    return .green
        case .partial: return .orange
        case .unpaid:  return .secondary
        case .overdue: return .red
        }
    }
}
