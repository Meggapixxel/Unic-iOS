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
@preconcurrency import FirebaseFirestore

/// Typed errors thrown by `FirebaseService` for known Firestore failure scenarios.
enum FirebaseError: LocalizedError {
    case documentNotFound
    case decodingFailed
    case missingId

    var errorDescription: String? {
        switch self {
        case .documentNotFound: return "Document not found in Firestore"
        case .decodingFailed:   return "Failed to decode Firestore document"
        case .missingId:        return "Document ID is missing"
        }
    }
}

/// A generic named tag backed by its Firestore document ID.
struct TagItem: Identifiable, Hashable {
    let id: String
    let name: String
}

typealias WorksOnTag = TagItem
typealias ArticleTag = TagItem

/// Main Firestore data service for the UNIC app.
///
/// Provides async methods for salons, status history, tags, users, plans, promos,
/// and barcode lookups. Also publishes a real-time salons snapshot via `startListening()`.
@MainActor
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

    private func decodeSalon(_ doc: DocumentSnapshot) -> Salon? {
        try? doc.data(as: Salon.self)
    }

    /// Fetches up to `limit` salons ordered by name and refreshes the `salons` publisher.
    /// - Parameter limit: Maximum number of documents to return (default 50).
    /// - Returns: Decoded `Salon` array.
    /// - Throws: A Firestore error if the query fails.
    func fetchSalons(limit: Int = 50) async throws -> [Salon] {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("salons")
            .order(by: "name")
            .limit(to: limit)
            .getDocuments()

        let salons = snapshot.documents.compactMap { decodeSalon($0) }
        AppLogger.log(.debug, "Firebase", "fetchSalons → \(salons.count) records")

        await MainActor.run {
            self.salons = salons
        }

        return salons
    }

    /// Fetches every salon in the collection (no limit) and refreshes the `salons` publisher.
    /// - Returns: All decoded `Salon` documents ordered by name.
    /// - Throws: A Firestore error if the query fails.
    func fetchAllSalons() async throws -> [Salon] {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("salons")
            .order(by: "name")
            .getDocuments()

        let salons = snapshot.documents.compactMap { decodeSalon($0) }

        await MainActor.run {
            self.salons = salons
        }

        return salons
    }

    // MARK: - Search

    /// Searches salons by name or address using a local case-insensitive filter (Firestore has no full-text search).
    /// - Parameter query: The search string; an empty query returns the first 50 salons.
    /// - Returns: Salons whose name or address contains the query.
    /// - Throws: A Firestore error if the underlying fetch fails.
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

    /// Fetches all salons that have a specific status, ordered by name.
    /// - Parameter status: The salon status to filter on.
    /// - Returns: Matching `Salon` documents.
    /// - Throws: A Firestore error if the query fails.
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

    /// Fetches a single salon by its Firestore document ID.
    /// - Parameter id: The salon's Firestore document ID.
    /// - Returns: The decoded `Salon`, or `nil` if the document does not exist.
    /// - Throws: A Firestore or decoding error.
    func getSalon(id: String) async throws -> Salon? {
        let doc = try await db.collection("salons").document(id).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: Salon.self)
    }

    // MARK: - Update Salon

    /// Updates only the `status` field of a salon document.
    func updateSalonStatus(salonId: String, status: SalonStatus) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "status": status.rawValue
        ])
    }

    /// Updates only the `notes` field of a salon document.
    func updateSalonNotes(salonId: String, notes: String) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "notes": notes
        ])
    }

    /// Updates the `leadTemp` field of a salon document; pass `nil` to clear it.
    func updateSalonLeadTemp(salonId: String, leadTemp: LeadTemp?) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "leadTemp": leadTemp?.rawValue as Any
        ])
    }

    /// Updates the `language` field (BCP-47 code) of a salon document.
    func updateSalonLanguage(salonId: String, language: String) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "language": language
        ])
    }

    /// Replaces the `worksOn` tag-ID array of a salon document.
    func updateSalonWorksOn(salonId: String, worksOn: [String]) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "worksOn": worksOn
        ])
    }

    // MARK: - Works On Tags

    @discardableResult
    func loadWorksOnTags() async -> [WorksOnTag] {
        do {
            let snapshot = try await db.collection("worksOnTags")
                .order(by: "name")
                .getDocuments()
            let tags = snapshot.documents.compactMap { doc -> WorksOnTag? in
                guard let name = doc.data()["name"] as? String else { return nil }
                return WorksOnTag(id: doc.documentID, name: name)
            }
            AppLogger.log(.debug, "Firebase", "loadWorksOnTags → \(tags.count) tags")
            worksOnTags = tags
            return tags
        } catch {
            AppLogger.log(.error, "Firebase", "loadWorksOnTags failed: \(error.localizedDescription)")
            self.error = error
            return worksOnTags
        }
    }

    /// Adds a new works-on tag, or returns the existing document ID if the name already exists.
    /// - Parameter name: The tag name to add.
    /// - Returns: The Firestore document ID of the existing or newly created tag.
    /// - Throws: A Firestore error if the write fails.
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

    /// Updates the `nextStep` free-text field of a salon document; pass `nil` to clear it.
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
            "salonId":   salonId,
            "name":      name,
            "status":    SalonStatus.new.rawValue,
            "language":  language,
            "createdAt": Timestamp(date: Date())
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

    /// Returns the most recent status-history entry for a salon, ordered by `timestamp` descending.
    /// - Returns: The latest `StatusHistoryEntry`, or `nil` if no entries exist.
    /// - Throws: A Firestore error if the query fails.
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

    /// Fetches the full status-history subcollection for a salon, newest first.
    /// - Returns: All decoded `StatusHistoryEntry` documents.
    /// - Throws: A Firestore error if the query fails.
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

    /// Appends a new status-history entry and denormalizes the latest entry onto the salon document.
    /// Also manages `testDriveStartDate` and `demoDate` fields based on the new status.
    /// - Parameters:
    ///   - salonId: The salon to update.
    ///   - status: The new salon status.
    ///   - note: An optional free-text note attached to the entry.
    ///   - createdBy: The UID of the user creating the entry.
    ///   - date: An explicit activity date; if `nil` the current date is used.
    ///   - userLocation: The GPS location of the user at the time of the entry, if available.
    func addStatusHistoryEntry(salonId: String, status: SalonStatus, note: String?, createdBy: String?, date: Date? = nil, userLocation: Location? = nil) async throws {
        AppLogger.log(.info, "Firebase", "addStatusEntry: salonId=\(salonId) status=\(status.rawValue)")
        let now = Timestamp(date: Date())
        var entry: [String: Any] = [
            "status": status.rawValue,
            "note": note as Any,
            "timestamp": now,
            "createdBy": createdBy as Any
        ]
        if let date { entry["date"] = Timestamp(date: date) }
        if let loc = userLocation { entry["userLocation"] = ["lat": loc.lat, "lng": loc.lng] }

        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .addDocument(data: entry)

        var salonUpdate: [String: Any] = [
            "status": status.rawValue,
            "latestStatusEntry": entry
        ]

        if status == .testDrive {
            salonUpdate["testDriveStartDate"] = now
        } else {
            salonUpdate["testDriveStartDate"] = FieldValue.delete()
        }

        if status == .demoScheduled, let date {
            salonUpdate["demoDate"] = Timestamp(date: date)
        } else if status != .demoScheduled {
            salonUpdate["demoDate"] = FieldValue.delete()
        }

        try await db.collection("salons").document(salonId).updateData(salonUpdate)

    }

    /// Deletes a single status-history document from the salon's `statusHistory` subcollection.
    func deleteStatusHistoryEntry(salonId: String, entryId: String) async throws {
        AppLogger.log(.info, "Firebase", "deleteStatusEntry: salonId=\(salonId) entryId=\(entryId)")
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .document(entryId)
            .delete()
    }

    /// Updates the `note` field on an existing status-history entry; pass `nil` to clear it.
    func updateStatusEntryNote(salonId: String, entryId: String, note: String?) async throws {
        try await db.collection("salons")
            .document(salonId)
            .collection("statusHistory")
            .document(entryId)
            .updateData(["note": note as Any])
    }

    // MARK: - Delete Salon

    /// Deletes a salon document from Firestore (hard delete — subcollections must be cleaned up separately).
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

    /// Fetches all user documents from the `users` collection.
    /// - Returns: Decoded `AppUser` array (without active-plan data).
    /// - Throws: A Firestore error if the query fails.
    func fetchAllUsers() async throws -> [AppUser] {
        AppLogger.log(.debug, "Firebase", "fetchAllUsers")
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            guard let role = UserRole(rawValue: d["role"] as? String ?? "") else { return nil }
            return AppUser(
                id: doc.documentID,
                firstName: d["first_name"] as? String ?? "",
                lastName: d["last_name"] as? String ?? "",
                role: role,
                activePlan: nil
            )
        }
    }

    /// Fetches all status-history entries created by a specific user across all salons,
    /// then resolves salon names in parallel using a `TaskGroup`.
    /// - Parameter userId: The Firestore UID to filter on.
    /// - Returns: Decoded `UserActivityEntry` array, newest first.
    /// - Throws: A Firestore error if the collection-group query fails.
    func fetchUserActivity(userId: String) async throws -> [UserActivityEntry] {
        AppLogger.log(.debug, "Firebase", "fetchUserActivity: userId=\(userId)")
        let snapshot = try await db.collectionGroup("statusHistory")
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .getDocuments()

        var salonNames: [String: String] = [:]
        let salonIds = Set(snapshot.documents.compactMap { salonId(from: $0.reference.path) })
        let db = self.db
        await withTaskGroup(of: (String, String).self) { group in
            for id in salonIds {
                group.addTask {
                    do {
                        let doc = try await db.collection("salons").document(id).getDocument()
                        return (id, doc.data()?["name"] as? String ?? id)
                    } catch {
                        return (id, id)
                    }
                }
            }
            for await (id, name) in group { salonNames[id] = name }
        }

        let entries = snapshot.documents.compactMap { doc -> UserActivityEntry? in
            guard let sid = salonId(from: doc.reference.path) else { return nil }
            let d = doc.data()
            let status = SalonStatus(rawValue: d["status"] as? String ?? "") ?? .new
            let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let raw = d["note"] as? String
            let loc = d["userLocation"] as? [String: Any]
            let lat = loc?["lat"] as? Double
            let lng = loc?["lng"] as? Double
            return UserActivityEntry(
                id: doc.documentID, salonId: sid, salonName: salonNames[sid] ?? sid,
                status: status, note: raw?.isEmpty == false ? raw : nil, timestamp: ts,
                latitude: lat, longitude: lng
            )
        }
        AppLogger.log(.debug, "Firebase", "fetchUserActivity → \(entries.count) entries")
        return entries
    }

    private func salonId(from path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        guard let idx = parts.firstIndex(of: "salons"), idx + 1 < parts.count else { return nil }
        return parts[idx + 1]
    }

    // MARK: - Test Drive Config

    @Published private(set) var testDriveDuration: Int = 7

    /// Loads the `testDrive.duration` value from the `config` collection and updates `testDriveDuration`.
    func loadTestDriveConfig() async {
        do {
            let doc = try await db.collection("config").document("testDrive").getDocument()
            guard let duration = doc.data()?["duration"] as? Int else {
                AppLogger.log(.warning, "Firebase", "loadTestDriveConfig: missing 'duration' field, using default 7")
                return
            }
            AppLogger.log(.info, "Firebase", "loadTestDriveConfig → duration: \(duration)")
            await MainActor.run { testDriveDuration = duration }
        } catch {
            AppLogger.log(.error, "Firebase", "loadTestDriveConfig failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Bundle Codes (starter kit exclusion list for stock movements)

    @Published private(set) var bundleCodes: Set<String> = []

    @discardableResult
    func loadBundleCodes() async -> Set<String> {
        do {
            let doc = try await db.collection("config").document("bundleCodes").getDocument()
            guard let codes = doc.data()?["codes"] as? [String] else {
                AppLogger.log(.warning, "Firebase", "loadBundleCodes: document missing or has no 'codes' field")
                return bundleCodes
            }
            AppLogger.log(.info, "Firebase", "loadBundleCodes → \(codes.count) bundle codes: \(codes.joined(separator: ", "))")
            bundleCodes = Set(codes)
            return bundleCodes
        } catch {
            AppLogger.log(.error, "Firebase", "loadBundleCodes failed: \(error.localizedDescription)")
            self.error = error
            return bundleCodes
        }
    }

    // MARK: - Barcode Lookup

    /// Looks up a barcode in the `barcodes` Firestore collection and returns the associated article code.
    /// - Parameter barcode: The scanned barcode string.
    /// - Returns: The FlexiBee article code, or `nil` if the barcode is not in the database.
    /// - Throws: A Firestore error if the document read fails.
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

    // MARK: - Plans

    /// Returns the currently active plan (one whose date range covers now), if any.
    /// - Returns: The active `Plan`, or `nil` if no plan is currently running.
    /// - Throws: A Firestore error if the query fails.
    func fetchActivePlan() async throws -> Plan? {
        let now = Timestamp(date: Date())
        let snapshot = try await db.collection("plans")
            .whereField("endDate", isGreaterThanOrEqualTo: now)
            .order(by: "endDate")
            .limit(to: 5)
            .getDocuments()
        let plans = snapshot.documents.compactMap { try? $0.data(as: Plan.self) }
        return plans.first { $0.isActive }
    }

    /// Fetches all plan documents ordered by `startDate` descending.
    /// - Returns: All decoded `Plan` documents.
    /// - Throws: A Firestore error if the query fails.
    func fetchAllPlans() async throws -> [Plan] {
        let snapshot = try await db.collection("plans")
            .order(by: "startDate", descending: true)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Plan.self) }
    }

    /// Creates or updates a plan document and returns the refreshed value.
    /// - Parameter plan: The plan to persist. If `plan.id` is `nil` a new document is created.
    /// - Returns: The saved `Plan` as read back from Firestore.
    /// - Throws: A Firestore or decoding error.
    func savePlan(_ plan: Plan) async throws -> Plan {
        let encoder = Firestore.Encoder()
        var data = try encoder.encode(plan)
        data.removeValue(forKey: "id")
        let docRef: DocumentReference
        if let id = plan.id {
            docRef = db.collection("plans").document(id)
            try await docRef.setData(data)
        } else {
            docRef = try await db.collection("plans").addDocument(data: data)
        }
        let doc = try await docRef.getDocument()
        guard let saved = try? doc.data(as: Plan.self) else {
            throw NSError(domain: "SavePlan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch saved plan"])
        }
        return saved
    }

    /// Deletes a plan document from Firestore.
    /// - Parameter id: The Firestore document ID of the plan to delete.
    func deletePlan(id: String) async throws {
        try await db.collection("plans").document(id).delete()
    }

    /// Fetches the default plan configuration from `config/defaultPlan`, if one has been set.
    /// - Returns: A `DefaultPlan`, or `nil` if the document does not exist.
    /// - Throws: A Firestore error if the read fails.
    func fetchDefaultPlan() async throws -> DefaultPlan? {
        AppLogger.log(.debug, "Firebase", "fetchDefaultPlan")
        let doc = try await db.collection("config").document("defaultPlan").getDocument()
        guard doc.exists, let d = doc.data() else {
            AppLogger.log(.debug, "Firebase", "fetchDefaultPlan → not found")
            return nil
        }
        return DefaultPlan(
            createdBy: d["createdBy"] as? String ?? "",
            targetSalons: d["targetSalons"] as? Int,
            targetSalonsPerDay: d["targetSalonsPerDay"] as? Int ?? 0,
            targetTestDrives: d["targetTestDrives"] as? Int,
            targetTestDrivesPerDay: d["targetTestDrivesPerDay"] as? Int ?? 0
        )
    }

    /// Fetches the plan-history subcollection for a user, ordered by result creation date descending.
    /// Only entries that include a `result` map are returned.
    /// - Parameter userId: The Firestore UID of the user.
    /// - Returns: Archived plan entries with their actuals.
    /// - Throws: A Firestore error if the query fails.
    func fetchPlanHistory(userId: String) async throws -> [UserPlanHistoryEntry] {
        AppLogger.log(.debug, "Firebase", "fetchPlanHistory: userId=\(userId)")
        let snapshot = try await db.collection("users").document(userId).collection("planHistory")
            .order(by: "result.createdAt", descending: true)
            .getDocuments()
        let entries = snapshot.documents.compactMap { doc -> UserPlanHistoryEntry? in
            let d = doc.data()
            guard let startTs     = d["startDate"]            as? Timestamp,
                  let endTs       = d["endDate"]              as? Timestamp,
                  let resultMap   = d["result"]               as? [String: Any],
                  let createdAtTs = resultMap["createdAt"]    as? Timestamp
            else { return nil }
            return UserPlanHistoryEntry(
                id: doc.documentID,
                startDate: startTs.dateValue(),
                endDate: endTs.dateValue(),
                targetSalons: d["targetSalons"] as? Int,
                targetSalonsPerDay: d["targetSalonsPerDay"] as? Int ?? 0,
                targetTestDrives: d["targetTestDrives"] as? Int,
                targetTestDrivesPerDay: d["targetTestDrivesPerDay"] as? Int ?? 0,
                result: PlanResult(
                    salons: resultMap["salons"] as? Int ?? 0,
                    testDrives: resultMap["testDrives"] as? Int ?? 0,
                    createdAt: createdAtTs.dateValue()
                )
            )
        }
        AppLogger.log(.debug, "Firebase", "fetchPlanHistory → \(entries.count) archived entries")
        return entries
    }

    /// Distributes a new plan to every user's `planHistory` subcollection.
    /// Before writing the new plan it archives any open (result-free) plan entry by counting
    /// the user's activity in that period and writing the result back.
    /// - Parameter plan: The plan to propagate to all users.
    /// - Throws: A Firestore error if any write fails (individual archive failures are swallowed).
    func setPlanForAllUsers(plan: Plan) async throws {
        AppLogger.log(.info, "Firebase", "setPlanForAllUsers: planId=\(plan.id ?? "new")")
        let usersSnapshot = try await db.collection("users").getDocuments()
        let userIds = usersSnapshot.documents.map { $0.documentID }
        AppLogger.log(.debug, "Firebase", "setPlanForAllUsers: processing \(userIds.count) users")

        for userId in userIds {
            let histSnapshot = try await db.collection("users").document(userId)
                .collection("planHistory")
                .order(by: "startDate", descending: true)
                .limit(to: 1)
                .getDocuments()

            if let currentDoc = histSnapshot.documents.first,
               currentDoc.data()["result"] == nil {
                let d = currentDoc.data()
                if let startTs = d["startDate"] as? Timestamp,
                   let endTs   = d["endDate"]   as? Timestamp {
                    let result = (try? await countActivityInPeriod(userId: userId, start: startTs.dateValue(), end: endTs.dateValue()))
                        ?? PlanResult(salons: 0, testDrives: 0, createdAt: Date())
                    AppLogger.log(.debug, "Firebase", "Archiving plan for userId=\(userId): salons=\(result.salons), testDrives=\(result.testDrives)")
                    try? await currentDoc.reference.updateData([
                        "result": [
                            "salons": result.salons,
                            "testDrives": result.testDrives,
                            "createdAt": Timestamp(date: result.createdAt)
                        ]
                    ])
                }
            }

            let docId = plan.id ?? UUID().uuidString
            var newData: [String: Any] = [
                "startDate": Timestamp(date: plan.startDate),
                "endDate": Timestamp(date: plan.endDate),
                "targetSalonsPerDay": plan.targetSalonsPerDay,
                "targetTestDrivesPerDay": plan.targetTestDrivesPerDay
            ]
            if let ts = plan.targetSalons     { newData["targetSalons"] = ts }
            if let td = plan.targetTestDrives { newData["targetTestDrives"] = td }
            try? await db.collection("users").document(userId)
                .collection("planHistory").document(docId).setData(newData)
        }

        AppLogger.log(.info, "Firebase", "setPlanForAllUsers: done for \(userIds.count) users")
    }

    private func countActivityInPeriod(userId: String, start: Date, end: Date) async throws -> PlanResult {
        let snapshot = try await db.collectionGroup("statusHistory")
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "timestamp")
            .getDocuments()
        let docs = snapshot.documents.filter {
            guard let ts = ($0.data()["timestamp"] as? Timestamp)?.dateValue() else { return false }
            return ts >= start && ts <= end
        }
        return PlanResult(
            salons: docs.count,
            testDrives: docs.filter { ($0.data()["status"] as? String) == SalonStatus.testDrive.rawValue }.count,
            createdAt: Date()
        )
    }

    // MARK: - Promo Offers

    /// Returns the list of promo category names from `config/promos`.
    func fetchPromoCategories() async throws -> [String] {
        let doc = try await db.collection("config").document("promos").getDocument()
        return doc.data()?["categories"] as? [String] ?? []
    }

    /// Fetches all promo-offer documents from the `promos` collection.
    func fetchPromos() async throws -> [PromoOffer] {
        let snapshot = try await db.collection("promos").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: PromoOffer.self) }
    }

    /// Creates or overwrites a promo-offer document and returns the refreshed value.
    /// - Parameter promo: The promo to persist. If `promo.id` is `nil` a new document is created.
    /// - Returns: The saved `PromoOffer` as read back from Firestore.
    func savePromo(_ promo: PromoOffer) async throws -> PromoOffer {
        let encoder = Firestore.Encoder()
        var data = try encoder.encode(promo)
        data.removeValue(forKey: "id")
        let docRef: DocumentReference
        if let id = promo.id {
            docRef = db.collection("promos").document(id)
        } else {
            docRef = db.collection("promos").document()
        }
        try await docRef.setData(data)
        return try await fetchPromo(ref: docRef)
    }

    /// Sets the `validFrom` and `validTo` timestamps on a promo, making it active.
    /// - Returns: The updated `PromoOffer`.
    func activatePromo(id: String, validFrom: Date, validTo: Date) async throws -> PromoOffer {
        let docRef = db.collection("promos").document(id)
        try await docRef.updateData([
            "validFrom": Timestamp(date: validFrom),
            "validTo":   Timestamp(date: validTo)
        ])
        return try await fetchPromo(ref: docRef)
    }

    /// Removes the `validFrom` and `validTo` fields from a promo, deactivating it.
    /// - Returns: The updated `PromoOffer`.
    func deactivatePromo(id: String) async throws -> PromoOffer {
        let docRef = db.collection("promos").document(id)
        try await docRef.updateData([
            "validFrom": FieldValue.delete(),
            "validTo":   FieldValue.delete()
        ])
        return try await fetchPromo(ref: docRef)
    }

    private func fetchPromo(ref: DocumentReference) async throws -> PromoOffer {
        let doc = try await ref.getDocument()
        guard doc.exists else { throw FirebaseError.documentNotFound }
        guard let saved = try? doc.data(as: PromoOffer.self) else { throw FirebaseError.decodingFailed }
        return saved
    }

    /// Deletes a promo-offer document from Firestore.
    func deletePromo(id: String) async throws {
        try await db.collection("promos").document(id).delete()
    }
}
