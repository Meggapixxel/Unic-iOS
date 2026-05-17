import Foundation
@preconcurrency import FirebaseFirestore

struct PromoContent: Codable, Equatable {
    var title: String
    var description: String
}

struct PromoOffer: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var content: [String: PromoContent]
    var validFrom: Date?
    var validTo: Date?
    let createdBy: String
    var category: String

    static let categories: [String] = [
        "Hair Color", "Developer", "Bleaching Powder",
        "Color Masks & Mousses", "Treatments", "Shampoo",
        "Hair Care", "Styling", "GRAVITY", "BROWIS", "Other"
    ]

    var isEnabled: Bool { validFrom != nil || validTo != nil }
    var isActive: Bool {
        guard let vf = validFrom, let vt = validTo else { return false }
        return Date() >= vf && Date() <= vt
    }
    var isPast: Bool {
        guard let vt = validTo else { return false }
        return Date() > vt
    }

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
        validFrom: Date? = nil,
        validTo: Date? = nil,
        createdBy: String,
        category: String = "Other",
        content: [String: PromoContent] = [:]
    ) {
        self.id = id
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdBy = createdBy
        self.category = category
        self.content = content.isEmpty ? ["en": PromoContent(title: title, description: description)] : content
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id       = try c.decode(DocumentID<String>.self, forKey: .id)
        validFrom = try? c.decode(Date.self, forKey: .validFrom)
        validTo   = try? c.decode(Date.self, forKey: .validTo)
        createdBy = try c.decode(String.self, forKey: .createdBy)
        category  = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        if let contentDict = try? c.decode([String: PromoContent].self, forKey: .content) {
            content = contentDict
        } else {
            let t = (try? c.decode(String.self, forKey: .title)) ?? ""
            let d = (try? c.decode(String.self, forKey: .description)) ?? ""
            content = ["en": PromoContent(title: t, description: d)]
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, content, validFrom, validTo, createdBy, category
        case title, description
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try _id.encode(to: encoder)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(validFrom, forKey: .validFrom)
        try c.encodeIfPresent(validTo, forKey: .validTo)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(category, forKey: .category)
    }
}
