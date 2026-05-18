import Foundation
@preconcurrency import FirebaseFirestore

/// Localised title and body text for a single language variant of a `PromoOffer`.
struct PromoContent: Codable, Equatable {
    var title: String
    var description: String
}

/// A promotional offer stored in Firestore, with multilingual content and an optional validity window.
struct PromoOffer: Codable, Identifiable, Equatable {
    /// Firestore document ID.
    @DocumentID var id: String?
    /// Localised content keyed by BCP-47 language code (e.g. `"en"`, `"uk"`).
    var content: [String: PromoContent]
    /// Start of the validity window; `nil` if no start constraint.
    var validFrom: Date?
    /// End of the validity window; `nil` if no end constraint.
    var validTo: Date?
    /// UID of the user who created the promo.
    let createdBy: String
    /// Product category this promo belongs to (see `categories`).
    var category: String
    /// Optional URL of a promotional image.
    var imageURL: String?

    /// Canonical list of product categories a promo can be assigned to.
    static let categories: [String] = [
        "Hair Color", "Developer", "Bleaching Powder",
        "Color Masks & Mousses", "Treatments", "Shampoo",
        "Hair Care", "Styling", "GRAVITY", "BROWIS", "Other"
    ]

    /// `true` when at least one date bound is set, indicating the promo has a validity window.
    var isEnabled: Bool { validFrom != nil || validTo != nil }
    /// `true` while the current date falls within `[validFrom, validTo]`.
    var isActive: Bool {
        guard let vf = validFrom, let vt = validTo else { return false }
        return Date() >= vf && Date() <= vt
    }
    /// `true` once `validTo` has passed.
    var isPast: Bool {
        guard let vt = validTo else { return false }
        return Date() > vt
    }

    /// English title, falling back to the first available language variant.
    var title: String { content["en"]?.title ?? content.values.first?.title ?? "" }
    /// English description, falling back to the first available language variant.
    var description: String { content["en"]?.description ?? content.values.first?.description ?? "" }

    /// Returns the title for the given app language, falling back to English and then any variant.
    /// - Parameter lang: Preferred display language.
    func localizedTitle(for lang: AppLanguage) -> String {
        content[lang.rawValue]?.title ?? content[AppLanguage.en.rawValue]?.title ?? content.values.first?.title ?? ""
    }

    /// Returns the description for the given app language, falling back to English and then any variant.
    /// - Parameter lang: Preferred display language.
    func localizedDescription(for lang: AppLanguage) -> String {
        content[lang.rawValue]?.description ?? content[AppLanguage.en.rawValue]?.description ?? content.values.first?.description ?? ""
    }

    /// Creates a new `PromoOffer`, optionally bootstrapping English content from plain `title`/`description` strings.
    /// - Parameters:
    ///   - id: Firestore document ID; `nil` for new documents.
    ///   - title: English title used when `content` is empty.
    ///   - description: English description used when `content` is empty.
    ///   - validFrom: Start of the validity window.
    ///   - validTo: End of the validity window.
    ///   - createdBy: UID of the creating user.
    ///   - category: Product category; defaults to `"Other"`.
    ///   - content: Full multilingual content map; takes precedence over `title`/`description`.
    init(
        id: String? = nil,
        title: String = "",
        description: String = "",
        validFrom: Date? = nil,
        validTo: Date? = nil,
        createdBy: String,
        category: String = "Other",
        content: [String: PromoContent] = [:],
        imageURL: String? = nil
    ) {
        self.id = id
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdBy = createdBy
        self.category = category
        self.content = content.isEmpty ? ["en": PromoContent(title: title, description: description)] : content
        self.imageURL = imageURL
    }

    /// Custom decoder that migrates legacy flat `title`/`description` fields into the `content` map.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id       = try c.decode(DocumentID<String>.self, forKey: .id)
        validFrom = try? c.decode(Date.self, forKey: .validFrom)
        validTo   = try? c.decode(Date.self, forKey: .validTo)
        createdBy = try c.decode(String.self, forKey: .createdBy)
        category  = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        imageURL  = try? c.decode(String.self, forKey: .imageURL)
        if let contentDict = try? c.decode([String: PromoContent].self, forKey: .content) {
            content = contentDict
        } else {
            let t = (try? c.decode(String.self, forKey: .title)) ?? ""
            let d = (try? c.decode(String.self, forKey: .description)) ?? ""
            content = ["en": PromoContent(title: t, description: d)]
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, content, validFrom, validTo, createdBy, category, imageURL
        case title, description
    }

    /// Custom encoder that writes only the `content` map, omitting legacy flat fields.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try _id.encode(to: encoder)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(validFrom, forKey: .validFrom)
        try c.encodeIfPresent(validTo, forKey: .validTo)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
    }
}
