//
//  FirebaseService.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

class FirebaseService: ObservableObject {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()

    @Published var salons: [Salon] = []
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

    func updateSalonNextStep(salonId: String, nextStep: String?) async throws {
        try await db.collection("salons").document(salonId).updateData([
            "nextStep": nextStep as Any
        ])
    }

    // MARK: - Status History

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
            case .ordered, .testing:
                batchA.updateData(["leadTemp": LeadTemp.A.rawValue], forDocument: ref)
                countA += 1
            case .contacted, .demoScheduled:
                batchB.updateData(["leadTemp": LeadTemp.B.rawValue], forDocument: ref)
                countB += 1
            case .new, .lost:
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
}
