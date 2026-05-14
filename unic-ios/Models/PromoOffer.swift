import Foundation
@preconcurrency import FirebaseFirestore

struct PromoOffer: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let validFrom: Date
    let validTo: Date
    let createdBy: String
    var category: String
    var isEnabled: Bool

    static let categories: [String] = [
        "Hair Color", "Developer", "Bleaching Powder",
        "Color Masks & Mousses", "Treatments", "Shampoo",
        "Hair Care", "Styling", "GRAVITY", "BROWIS", "Other"
    ]

    var isActive: Bool { Date() >= validFrom && Date() <= validTo }
    var isPast: Bool { Date() > validTo }

    init(
        id: String? = nil,
        title: String,
        description: String,
        validFrom: Date,
        validTo: Date,
        createdBy: String,
        category: String = "Other",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdBy = createdBy
        self.category = category
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id         = try c.decode(DocumentID<String>.self, forKey: .id)
        title       = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        validFrom   = try c.decode(Date.self, forKey: .validFrom)
        validTo     = try c.decode(Date.self, forKey: .validTo)
        createdBy   = try c.decode(String.self, forKey: .createdBy)
        category    = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        isEnabled   = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
    }
}
