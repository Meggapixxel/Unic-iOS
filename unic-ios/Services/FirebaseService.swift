//
//  FirebaseService.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import Combine
import CoreLocation
import FirebaseCore
import FirebaseFirestore

struct TagItem: Identifiable, Hashable {
    let id: String
    let name: String
}

typealias WorksOnTag = TagItem
typealias ArticleTag = TagItem

final class FirebaseService: ObservableObject {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()

    @Published var salons: [Salon] = []
    @Published var worksOnTags: [WorksOnTag] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var listener: ListenerRegistration?

    init() {}

    // MARK: - Fetch Salons

    func fetchSalons(limit: Int = 50) async throws -> [Salon] {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("salons")
            .order(by: "name")
            .limit(to: limit)
            .getDocuments()

        let salons = snapshot.documents.compactMap { doc -> Salon? in
            try? doc.data(as: Salon.self)
        }

        await MainActor.run {
            self.salons = salons
        }

        return salons
    }

    func fetchAllSalons() async throws -> [Salon] {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("salons")
            .order(by: "name")
            .getDocuments()

        let salons = snapshot.documents.compactMap { doc -> Salon? in
            try? doc.data(as: Salon.self)
        }

        await MainActor.run {
            self.salons = salons
        }

        return salons
    }

    // MARK: - Search

    func searchSalons(query: String) async throws -> [Salon] {
        guard !query.isEmpty else {
            return try await fetchSalons()
        }

        // Firestore doesn't support full-text search, so we fetch and filter locally
        let allSalons = try await fetchAllSalons()

        let lowercasedQuery = query.lowercased()
        return allSalons.filter { salon in
            salon.name.lowercased().contains(lowercasedQuery) ||
            (salon.address?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }

    // MARK: - Filter by Status

    func fetchSalonsByStatus(_ status: SalonStatus) async throws -> [Salon] {
        let snapshot = try await db.collection("salons")
            .whereField("status", isEqualTo: status.rawValue)
            .order(by: "name")
            .getDocuments()

        return snapshot.documents.compactMap { doc -> Salon? in
            try? doc.data(as: Salon.self)
        }
    }

    // MARK: - Get Single Salon

    func getSalon(id: String) async throws -> Salon? {
        let doc = try await db.collection("salons").document(id).getDocument()
        return try? doc.data(as: Salon.self)
    }

    // MARK: - Update Salon

    func updateSalonStatus(salonId: String, status: SalonStatus) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "status": status.rawValue
        ])
    }

    func updateSalonNotes(salonId: String, notes: String) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "notes": notes
        ])
    }

    func updateSalonLeadTemp(salonId: String, leadTemp: LeadTemp?) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "leadTemp": leadTemp?.rawValue as Any
        ])
    }

    func updateSalonCategory(salonId: String, category: SalonCategory?) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "salonCategory": category?.rawValue as Any
        ])
    }

    func updateSalonLanguage(salonId: String, language: String) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "language": language
        ])
    }

    func updateSalonWorksOn(salonId: String, worksOn: [String]) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "worksOn": worksOn
        ])
    }

    // MARK: - Works On Tags

    func loadWorksOnTags() async {
        guard let snapshot = try? await db.collection("worksOnTags")
            .order(by: "name")
            .getDocuments()
        else { return }
        let tags = snapshot.documents.compactMap { doc -> WorksOnTag? in
            guard let name = doc.data()["name"] as? String else { return nil }
            return WorksOnTag(id: doc.documentID, name: name)
        }
        await MainActor.run { worksOnTags = tags }
    }

    func addWorksOnTag(_ name: String) async throws -> String {
        let existing = try await db.collection("worksOnTags")
            .whereField("name", isEqualTo: name)
            .getDocuments()
        if let doc = existing.documents.first {
            return doc.documentID
        }
        let ref = try await db.collection("worksOnTags").addDocument(data: ["name": name])
        let newTag = WorksOnTag(id: ref.documentID, name: name)
        await MainActor.run {
            worksOnTags.append(newTag)
            worksOnTags.sort { $0.name < $1.name }
        }
        return ref.documentID
    }

    func updateSalonNextStep(salonId: String, nextStep: String?) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "nextStep": nextStep as Any
        ])
    }

    // MARK: - Create Salon

    func createSalon(
        name: String,
        city: String?,
        address: String?,
        phone: String?,
        instagram: String?,
        website: String?,
        facebook: String?,
        language: String,
        salonCategory: SalonCategory?,
        worksOn: [String],
        leadTemp: LeadTemp?,
        notes: String?
    ) async throws -> Salon {
        let ref = db.collection("salons").document()
        let salonId = ref.documentID

        var data: [String: Any] = [
            "salonId": salonId,
            "name": name,
            "status": SalonStatus.new.rawValue,
            "language": language
        ]

        if let leadTemp { data["leadTemp"] = leadTemp.rawValue }

        if let city { data["city"] = city }
        if let address { data["address"] = address }
        if let salonCategory { data["salonCategory"] = salonCategory.rawValue }
        if !worksOn.isEmpty { data["worksOn"] = worksOn }
        if let notes { data["notes"] = notes }

        // Geocode address → store in maps.location
        let query = [address, city].compactMap { $0 }.joined(separator: ", ")
        if !query.isEmpty, let coords = await geocode(query) {
            data["maps"] = [
                "location": ["lat": coords.latitude, "lng": coords.longitude],
                "source": "manual",
                "provider": "apple"
            ]
        }

        var contacts: [String: Any] = [:]
        if let phone {
            contacts["phone"] = ["value": phone, "isPrimary": true]
        }
        if let instagram {
            let handle = instagram.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            contacts["instagram"] = ["value": "https://www.instagram.com/\(handle)/", "isPrimary": true]
        }
        if let website {
            let url = website.hasPrefix("http") ? website : "https://\(website)"
            contacts["website"] = ["value": url, "isPrimary": true]
        }
        if let facebook {
            contacts["facebook"] = ["value": facebook, "isPrimary": true]
        }
        if !contacts.isEmpty {
            data["contacts"] = contacts
        }

        try await ref.setData(data)

        guard let salon = try await getSalon(id: salonId) else {
            throw NSError(domain: "AddSalon", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch created salon"])
        }
        return salon
    }

    // MARK: - Update Basic Info

    func updateSalonBasicInfo(
        salonId: String,
        name: String,
        city: String?,
        address: String?,
        phone: String?,
        instagram: String?,
        website: String?,
        facebook: String?,
        notes: String?,
        language: String,
        salonCategory: SalonCategory?,
        leadTemp: LeadTemp?,
        worksOn: [String],
        previousAddress: String?,
        previousCity: String?
    ) async throws -> Salon {
        var data: [String: Any] = ["name": name]

        data["city"]     = city as Any
        data["address"]  = address as Any
        data["notes"]    = notes as Any
        data["language"] = language
        data["salonCategory"] = salonCategory?.rawValue as Any
        data["leadTemp"]      = leadTemp?.rawValue as Any
        data["worksOn"]    = worksOn.isEmpty ? FieldValue.delete() : worksOn

        let locationChanged = address != previousAddress || city != previousCity
        let query = [address, city].compactMap { $0 }.joined(separator: ", ")
        if locationChanged, !query.isEmpty, let coords = await geocode(query) {
            data["maps.location"] = ["lat": coords.latitude, "lng": coords.longitude]
            data["maps.source"]   = "manual"
            data["maps.provider"] = "apple"
        }

        if let phone {
            data["contacts.phone"] = ["value": phone, "isPrimary": true]
        } else {
            data["contacts.phone"] = FieldValue.delete()
        }
        if let instagram {
            let handle = instagram.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            data["contacts.instagram"] = ["value": "https://www.instagram.com/\(handle)/", "isPrimary": true]
        } else {
            data["contacts.instagram"] = FieldValue.delete()
        }
        if let website {
            let url = website.hasPrefix("http") ? website : "https://\(website)"
            data["contacts.website"] = ["value": url, "isPrimary": true]
        } else {
            data["contacts.website"] = FieldValue.delete()
        }
        if let facebook {
            data["contacts.facebook"] = ["value": facebook, "isPrimary": true]
        } else {
            data["contacts.facebook"] = FieldValue.delete()
        }

        try await db.collection("salons").document(salonId).updateData(data)

        guard let salon = try await getSalon(id: salonId) else {
            throw NSError(domain: "EditSalon", code: -1)
        }
        return salon
    }

    // MARK: - Status History

    func fetchLatestStatusEntry(salonId: String) async throws -> StatusHistoryEntry? {
        let snapshot = try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: StatusHistoryEntry.self) }
    }

    func fetchStatusHistory(salonId: String) async throws -> [StatusHistoryEntry] {
        let snapshot = try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .order(by: "timestamp", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> StatusHistoryEntry? in
            try? doc.data(as: StatusHistoryEntry.self)
        }
    }

    func addStatusHistoryEntry(salonId: String, status: SalonStatus, note: String?) async throws {
        let entry: [String: Any] = [
            "status": status.rawValue,
            "note": note as Any,
            "timestamp": Timestamp(date: Date())
        ]

        // Add to history subcollection
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .addDocument(data: entry)

        // Update current status on salon
        try await updateSalonStatus(salonId: salonId, status: status)
    }

    func deleteStatusHistoryEntry(salonId: String, entryId: String) async throws {
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .document(entryId)
            .delete()
    }

    // MARK: - Delete Salon

    func deleteSalon(salonId: String) async throws {
        try await db.collection("salons").document(salonId).delete()
    }

    // MARK: - Batch Update LeadTemp

    /// Sets default leadTemp for all salons where it's currently nil
    func setDefaultLeadTempForAll(defaultTemp: LeadTemp = .C) async throws -> Int {
        let snapshot = try await db.collection("salons")
            .whereField("leadTemp", isEqualTo: NSNull())
            .getDocuments()

        let batch = db.batch()
        var count = 0

        for document in snapshot.documents {
            batch.updateData(["leadTemp": defaultTemp.rawValue], forDocument: document.reference)
            count += 1
        }

        if count > 0 {
            try await batch.commit()
        }

        return count
    }

    /// Sets leadTemp for a specific list of salon IDs
    func batchUpdateLeadTemp(salonIds: [String], leadTemp: LeadTemp) async throws {
        let batch = db.batch()

        for salonId in salonIds {
            let ref = db.collection("salons").document(salonId)
            batch.updateData(["leadTemp": leadTemp.rawValue], forDocument: ref)
        }

        try await batch.commit()
    }

    /// Sets leadTemp based on status (e.g., "ordered" -> A, "contacted" -> B, "new" -> C)
    func setLeadTempBasedOnStatus() async throws -> (a: Int, b: Int, c: Int) {
        let allSalons = try await fetchAllSalons()

        let batchA = db.batch()
        let batchB = db.batch()
        let batchC = db.batch()

        var countA = 0
        var countB = 0
        var countC = 0

        for salon in allSalons where salon.leadTemp == nil {
            let ref = db.collection("salons").document(salon.salonId)

            switch salon.statusEnum {
            case .ordered, .testDrive:
                batchA.updateData(["leadTemp": LeadTemp.A.rawValue], forDocument: ref)
                countA += 1
            case .contacted, .demoScheduled:
                batchB.updateData(["leadTemp": LeadTemp.B.rawValue], forDocument: ref)
                countB += 1
            case .new, .other:
                batchC.updateData(["leadTemp": LeadTemp.C.rawValue], forDocument: ref)
                countC += 1
            }
        }

        if countA > 0 { try await batchA.commit() }
        if countB > 0 { try await batchB.commit() }
        if countC > 0 { try await batchC.commit() }

        return (countA, countB, countC)
    }

    // MARK: - Real-time Listener

    func startListening() {
        listener = db.collection("salons")
            .order(by: "name")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.error = error
                    return
                }

                self?.salons = snapshot?.documents.compactMap { doc -> Salon? in
                    try? doc.data(as: Salon.self)
                } ?? []
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Geocoding

    private func geocode(_ query: String) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }
    }
}
