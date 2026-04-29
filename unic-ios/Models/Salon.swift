//
//  Salon.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import FirebaseFirestore

struct Location: Codable, Hashable {
    let lat: Double
    let lng: Double
}

struct Maps: Codable, Hashable {
    let provider: String?
    let mapsUrl: String?
    let placeId: String?
    let location: Location?
    let source: String?
    let confidence: Double?
}

struct Contact: Codable, Hashable {
    let value: String?
    let alt: String?
    let foundFrom: String?
    let isPrimary: Bool?
    let confidence: Double?
}

struct Contacts: Codable, Hashable {
    let website: Contact?
    let phone: Contact?
    let email: Contact?
    let instagram: Contact?
    let facebook: Contact?
    let tiktok: Contact?
}

struct Source: Codable, Hashable {
    let type: String?
    let file: String?
    let referrer: String?
}

enum LeadTemp: String, Codable, CaseIterable {
    case A = "A"
    case B = "B"
    case C = "C"
}

enum SalonCategory: String, Codable, CaseIterable {
    case A = "A"
    case B = "B"
    case C = "C"
}

enum SalonStatus: String, Codable, CaseIterable, Identifiable {
    case new = "new"
    case contacted = "contacted"
    case testDrive = "test_drive"
    case demoScheduled = "demo_scheduled"
    case ordered = "ordered"
    case other = "other"

    var id: String { rawValue }
}

struct Salon: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    let salonId: String
    let name: String
    let city: String?
    let address: String?
    let categoryName: String?
    let category: [String]?
    let tags: [String]?

    let maps: Maps?
    let contacts: Contacts?

    let leadTemp: String?
    let status: String?
    let ownerDriven: Bool?
    let notes: String?
    let worksOn: [String]?
    let language: String?
    let nextStep: String?

    let salonCategory: String?
    let source: Source?
    let enrichmentStatus: String?
    let enrichmentBatch: String?
    let googlePlacesTypes: [String]?
    let createdBy: String?
    let latestStatusEntry: StatusHistoryEntry?

    // Computed properties
    var displayName: String {
        name.isEmpty ? String(localized: "unnamed_salon") : name
    }

    var phoneNumber: String? {
        contacts?.phone?.value
    }

    var instagramHandle: String? {
        guard let url = contacts?.instagram?.value else { return nil }
        return url.replacingOccurrences(of: "https://www.instagram.com/", with: "@")
            .replacingOccurrences(of: "https://instagram.com/", with: "@")
            .replacingOccurrences(of: "/", with: "")
    }

    var websiteURL: URL? {
        guard let urlString = contacts?.website?.value else { return nil }
        return URL(string: urlString)
    }

    var googleMapsURL: URL? {
        guard let urlString = maps?.mapsUrl else { return nil }
        return URL(string: urlString)
    }

    var statusEnum: SalonStatus {
        SalonStatus(rawValue: status ?? "new") ?? .new
    }

    var leadTempEnum: LeadTemp? {
        guard let temp = leadTemp else { return nil }
        return LeadTemp(rawValue: temp)
    }

    var salonCategoryEnum: SalonCategory? {
        guard let cat = salonCategory else { return nil }
        return SalonCategory(rawValue: cat)
    }
}
