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
            do { return try doc.data(as: Salon.self) } catch { return nil }
        }
        AppLogger.log(.debug, "Firebase", "fetchSalons → \(salons.count) records")

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
            do { return try doc.data(as: Salon.self) } catch { return nil }
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
            do { return try doc.data(as: Salon.self) } catch { return nil }
        }
    }

    // MARK: - Get Single Salon

    func getSalon(id: String) async throws -> Salon? {
        let doc = try await db.collection("salons").document(id).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: Salon.self)
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
        do {
            let snapshot = try await db.collection("worksOnTags")
                .order(by: "name")
                .getDocuments()
            let tags = snapshot.documents.compactMap { doc -> WorksOnTag? in
                guard let name = doc.data()["name"] as? String else { return nil }
                return WorksOnTag(id: doc.documentID, name: name)
            }
            AppLogger.log(.debug, "Firebase", "loadWorksOnTags → \(tags.count) tags")
            await MainActor.run { worksOnTags = tags }
        } catch {
            AppLogger.log(.error, "Firebase", "loadWorksOnTags failed: \(error.localizedDescription)")
            await MainActor.run { self.error = error }
        }
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
        worksOn: [String],
        leadTemp: LeadTemp?,
        notes: String?,
        createdBy: String? = nil
    ) async throws -> Salon {
        let ref = db.collection("salons").document()
        let salonId = ref.documentID

        var data: [String: Any] = [
            "salonId": salonId,
            "name": name,
            "status": SalonStatus.new.rawValue,
            "language": language
        ]
        if let createdBy { data["createdBy"] = createdBy }

        if let leadTemp { data["leadTemp"] = leadTemp.rawValue }

        if let city { data["city"] = city }
        if let address { data["address"] = address }
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

        AppLogger.log(.info, "Firebase", "createSalon: \(name) id=\(salonId)")
        try await ref.setData(data)
        AppLogger.log(.info, "Firebase", "createSalon written: id=\(salonId)")

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

        AppLogger.log(.info, "Firebase", "updateSalonBasicInfo: id=\(salonId) name=\(name)")
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
        guard let doc = snapshot.documents.first else { return nil }
        return try doc.data(as: StatusHistoryEntry.self)
    }

    func fetchStatusHistory(salonId: String) async throws -> [StatusHistoryEntry] {
        let snapshot = try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .order(by: "timestamp", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> StatusHistoryEntry? in
            do { return try doc.data(as: StatusHistoryEntry.self) } catch { return nil }
        }
    }

    func addStatusHistoryEntry(salonId: String, status: SalonStatus, currentStatus: SalonStatus?, note: String?, createdBy: String?) async throws {
        AppLogger.log(.info, "Firebase", "addStatusEntry: salonId=\(salonId) status=\(status.rawValue)")
        let now = Timestamp(date: Date())
        let entry: [String: Any] = [
            "status": status.rawValue,
            "note": note as Any,
            "timestamp": now,
            "createdBy": createdBy as Any
        ]

        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .addDocument(data: entry)

        var salonUpdate: [String: Any] = [
            "status": status.rawValue,
            "latestStatusEntry": [
                "status": status.rawValue,
                "note": note as Any,
                "timestamp": now,
                "createdBy": createdBy as Any
            ] as [String: Any]
        ]

        if status == .testDrive && currentStatus != .testDrive {
            salonUpdate["testDriveStartDate"] = now
        } else if status != .testDrive {
            salonUpdate["testDriveStartDate"] = FieldValue.delete()
        }

        try await db.collection("salons").document(salonId).updateData(salonUpdate)
    }

    func deleteStatusHistoryEntry(salonId: String, entryId: String) async throws {
        AppLogger.log(.info, "Firebase", "deleteStatusEntry: salonId=\(salonId) entryId=\(entryId)")
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .document(entryId)
            .delete()
    }

    func updateStatusEntryNote(salonId: String, entryId: String, note: String?) async throws {
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .document(entryId)
            .updateData(["note": note as Any])
    }

    // MARK: - Delete Salon

    func deleteSalon(salonId: String) async throws {
        AppLogger.log(.info, "Firebase", "deleteSalon: id=\(salonId)")
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
        AppLogger.log(.info, "Firebase", "startListening: salons collection")
        listener = db.collection("salons")
            .order(by: "name")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    AppLogger.log(.error, "Firebase", "salons listener error: \(error.localizedDescription)")
                    self?.error = error
                    return
                }
                let count = snapshot?.documents.count ?? 0
                AppLogger.log(.debug, "Firebase", "salons snapshot: \(count) documents")
                self?.salons = snapshot?.documents.compactMap { doc -> Salon? in
                    do { return try doc.data(as: Salon.self) } catch { return nil }
                } ?? []
            }
    }

    func stopListening() {
        AppLogger.log(.info, "Firebase", "stopListening: salons collection")
        listener?.remove()
        listener = nil
    }

    // MARK: - Users

    func fetchAllUsers() async throws -> [AppUser] {
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            guard let role = UserRole(rawValue: d["role"] as? String ?? "") else { return nil }
            return AppUser(
                id: doc.documentID,
                firstName: d["first_name"] as? String ?? "",
                lastName: d["last_name"] as? String ?? "",
                role: role
            )
        }
    }

    func fetchUserActivity(userId: String) async throws -> [UserActivityEntry] {
        let snapshot = try await db.collectionGroup("statusHistory")
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .getDocuments()

        var salonNames: [String: String] = [:]
        let salonIds = Set(snapshot.documents.compactMap { salonId(from: $0.reference.path) })
        await withTaskGroup(of: (String, String).self) { group in
            for id in salonIds {
                group.addTask {
                    do {
                        let doc = try await self.db.collection("salons").document(id).getDocument()
                        return (id, doc.data()?["name"] as? String ?? id)
                    } catch {
                        return (id, id)
                    }
                }
            }
            for await (id, name) in group { salonNames[id] = name }
        }

        return snapshot.documents.compactMap { doc -> UserActivityEntry? in
            guard let sid = salonId(from: doc.reference.path) else { return nil }
            let d = doc.data()
            let status = SalonStatus(rawValue: d["status"] as? String ?? "") ?? .new
            let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let raw = d["note"] as? String
            return UserActivityEntry(
                id: doc.documentID, salonId: sid, salonName: salonNames[sid] ?? sid,
                status: status, note: raw?.isEmpty == false ? raw : nil, timestamp: ts
            )
        }
    }

    private func salonId(from path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        guard let idx = parts.firstIndex(of: "salons"), idx + 1 < parts.count else { return nil }
        return parts[idx + 1]
    }

    // MARK: - Bundle Codes (starter kit exclusion list for stock movements)

    @Published private(set) var bundleCodes: Set<String> = []

    func loadBundleCodes() async {
        do {
            let doc = try await db.collection("config").document("bundleCodes").getDocument()
            guard let codes = doc.data()?["codes"] as? [String] else {
                AppLogger.log(.warning, "Firebase", "loadBundleCodes: document missing or has no 'codes' field")
                return
            }
            AppLogger.log(.info, "Firebase", "loadBundleCodes → \(codes.count) bundle codes: \(codes.joined(separator: ", "))")
            await MainActor.run { bundleCodes = Set(codes) }
        } catch {
            AppLogger.log(.error, "Firebase", "loadBundleCodes failed: \(error.localizedDescription)")
            await MainActor.run { self.error = error }
        }
    }

    // MARK: - Barcode Lookup

    func lookupBarcodeArticle(_ barcode: String) async throws -> String? {
        let doc = try await db.collection("barcodes").document(barcode).getDocument()
        guard doc.exists else { return nil }
        return doc.data()?["article"] as? String
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
