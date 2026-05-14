import Foundation
@preconcurrency import FirebaseFirestore

struct PromoContent: Codable, Equatable {
    var title: String
    var description: String
}

struct PromoOffer: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var content: [String: PromoContent]
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

    var title: String { content["en"]?.title ?? content.values.first?.title ?? "" }
    var description: String { content["en"]?.description ?? content.values.first?.description ?? "" }

    func localizedTitle(for lang: AppLanguage) -> String {
        content[lang.rawValue]?.title ?? content[AppLanguage.en.rawValue]?.title ?? content.values.first?.title ?? ""
    }

    func localizedDescription(for lang: AppLanguage) -> String {
        content[lang.rawValue]?.description ?? content[AppLanguage.en.rawValue]?.description ?? content.values.first?.description ?? ""
    }

    init(
        id: String? = nil,
        title: String = "",
        description: String = "",
        validFrom: Date,
        validTo: Date,
        createdBy: String,
        category: String = "Other",
        isEnabled: Bool = true,
        content: [String: PromoContent] = [:]
    ) {
        self.id = id
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdBy = createdBy
        self.category = category
        self.isEnabled = isEnabled
        self.content = content.isEmpty ? ["en": PromoContent(title: title, description: description)] : content
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id       = try c.decode(DocumentID<String>.self, forKey: .id)
        validFrom = try c.decode(Date.self, forKey: .validFrom)
        validTo   = try c.decode(Date.self, forKey: .validTo)
        createdBy = try c.decode(String.self, forKey: .createdBy)
        category  = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        if let contentDict = try? c.decode([String: PromoContent].self, forKey: .content) {
            content = contentDict
        } else {
            let t = (try? c.decode(String.self, forKey: .title)) ?? ""
            let d = (try? c.decode(String.self, forKey: .description)) ?? ""
            content = ["en": PromoContent(title: t, description: d)]
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, content, validFrom, validTo, createdBy, category, isEnabled
        case title, description
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try _id.encode(to: encoder)
        try c.encode(content, forKey: .content)
        try c.encode(validFrom, forKey: .validFrom)
        try c.encode(validTo, forKey: .validTo)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(category, forKey: .category)
        try c.encode(isEnabled, forKey: .isEnabled)
    }
}
