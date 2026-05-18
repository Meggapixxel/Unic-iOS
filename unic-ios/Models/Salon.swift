//
//  Salon.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
@preconcurrency import FirebaseFirestore

/// Geographic coordinates of a salon or user check-in.
struct Location: Codable, Hashable {
    let lat: Double
    let lng: Double
}

/// Map metadata enriched from Google Places or a similar provider.
struct Maps: Codable, Hashable {
    /// Name of the mapping provider (e.g. `"google_places"`).
    let provider: String?
    /// Deep-link URL to the location in Google Maps.
    let mapsUrl: String?
    /// Google Places place ID.
    let placeId: String?
    let location: Location?
    /// Enrichment data source identifier.
    let source: String?
    /// Confidence score of the geocoding result (0–1).
    let confidence: Double?
}

/// A single contact channel (phone, email, website, social) with enrichment metadata.
struct Contact: Codable, Hashable {
    /// Primary value for this channel (URL, phone number, email address, etc.).
    let value: String?
    /// Alternative or secondary value for the same channel.
    let alt: String?
    /// Source from which this contact was discovered (e.g. `"instagram_bio"`).
    let foundFrom: String?
    /// Whether this is the primary contact for the channel.
    let isPrimary: Bool?
    /// Enrichment confidence score (0–1).
    let confidence: Double?
}

/// Aggregated contact channels for a salon.
struct Contacts: Codable, Hashable {
    let website: Contact?
    let phone: Contact?
    let email: Contact?
    let instagram: Contact?
    let facebook: Contact?
    let tiktok: Contact?
}

/// Origin of the salon record in the database (import file, referral, manual entry, etc.).
struct Source: Codable, Hashable {
    /// Source type identifier (e.g. `"csv_import"`, `"manual"`).
    let type: String?
    /// Filename or identifier of the import batch, if applicable.
    let file: String?
    /// Referrer or campaign that produced this record.
    let referrer: String?
}

/// Lead temperature rating used to prioritise outreach (A = hottest, C = coldest).
enum LeadTemp: String, Codable, CaseIterable {
    case A = "A"
    case B = "B"
    case C = "C"
}

/// Sales pipeline stage for a salon, progressing from first contact through to ordering.
enum SalonStatus: String, Codable, CaseIterable, Identifiable {
    case new = "new"
    case contacted = "contacted"
    case testDrive = "test_drive"
    case demoScheduled = "demo_scheduled"
    case ordered = "ordered"
    case other = "other"

    var id: String { rawValue }
}

/// A hair or beauty salon prospect stored in Firestore and tracked through the sales pipeline.
struct Salon: Codable, Identifiable, Hashable {
    /// Firestore document ID.
    @DocumentID var id: String?
    /// Stable business identifier (distinct from the Firestore document ID).
    let salonId: String
    let name: String
    let city: String?
    let address: String?
    /// Human-readable business type label.
    let categoryName: String?
    /// Raw category codes from the data source.
    let category: [String]?
    /// Freeform searchable tags.
    let tags: [String]?

    let maps: Maps?
    let contacts: Contacts?

    /// Raw lead temperature string; use `leadTempEnum` for typed access.
    let leadTemp: String?
    /// Raw pipeline status string; use `statusEnum` for typed access.
    var status: String?
    /// Whether the salon is primarily owner-operated.
    let ownerDriven: Bool?
    let notes: String?
    /// Products or brands the salon currently works with.
    let worksOn: [String]?
    /// Preferred communication language code.
    let language: String?
    /// Planned next action for the sales rep.
    let nextStep: String?

    let source: Source?
    /// Current enrichment pipeline status (e.g. `"enriched"`, `"pending"`).
    let enrichmentStatus: String?
    /// Identifier of the enrichment processing batch.
    let enrichmentBatch: String?
    /// Google Places type labels (e.g. `["hair_care", "beauty_salon"]`).
    let googlePlacesTypes: [String]?
    /// UID of the user who created or imported this salon record.
    let createdBy: String?
    /// Denormalised copy of the most recent status change for fast list rendering.
    let latestStatusEntry: StatusHistoryEntry?
    /// Date the test-drive phase began.
    let testDriveStartDate: Date?
    /// Scheduled demo appointment date.
    let demoDate: Date?
    var createdAt: Date?

    // Computed properties
    /// Salon name, falling back to a localised placeholder when the name is empty.
    var displayName: String {
        name.isEmpty ? String.unnamed_salon : name
    }

    /// Primary phone number extracted from `contacts`.
    var phoneNumber: String? {
        contacts?.phone?.value
    }

    /// Instagram handle formatted with a leading `@`, derived from the full profile URL.
    var instagramHandle: String? {
        guard let url = contacts?.instagram?.value else { return nil }
        return url.replacingOccurrences(of: "https://www.instagram.com/", with: "@")
            .replacingOccurrences(of: "https://instagram.com/", with: "@")
            .replacingOccurrences(of: "/", with: "")
    }

    /// Validated `URL` for the salon's website, or `nil` if unavailable or malformed.
    var websiteURL: URL? {
        guard let urlString = contacts?.website?.value else { return nil }
        return URL(string: urlString)
    }

    /// Deep-link `URL` to the salon in Google Maps, or `nil` if unavailable.
    var googleMapsURL: URL? {
        guard let urlString = maps?.mapsUrl else { return nil }
        return URL(string: urlString)
    }

    /// Typed pipeline status, defaulting to `.new` when the raw value is absent or unrecognised.
    var statusEnum: SalonStatus {
        SalonStatus(rawValue: status ?? "new") ?? .new
    }

    /// Typed lead temperature, or `nil` when not set.
    var leadTempEnum: LeadTemp? {
        guard let temp = leadTemp else { return nil }
        return LeadTemp(rawValue: temp)
    }

}
