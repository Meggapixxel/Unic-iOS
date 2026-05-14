import SwiftUI

extension PaymentStatus {
    var color: Color {
        switch self {
        case .paid:    return .green
        case .partial: return .orange
        case .unpaid:  return .secondary
        case .overdue: return .red
        }
    }
}
