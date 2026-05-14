import Foundation
@preconcurrency import FirebaseFirestore

struct PromoOffer: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let validFrom: Date
    let validTo: Date
    let createdBy: String

    var isActive: Bool { Date() >= validFrom && Date() <= validTo }
    var isPast: Bool { Date() > validTo }
}
