import ComposableArchitecture
import Foundation

@DependencyClient
struct FirebaseClient: @unchecked Sendable {
    // Salons
    var fetchSalons: () async throws -> [Salon] = { [] }
    var fetchAllSalons: () async throws -> [Salon] = { [] }
    var updateSalonStatus: (_ id: String, _ status: SalonStatus, _ note: String, _ createdBy: String) async throws -> Void
    var updateSalonNotes: (_ id: String, _ notes: String) async throws -> Void
    var updateSalonLeadTemp: (_ id: String, _ temp: LeadTemp) async throws -> Void
    var updateSalonWorksOn: (_ id: String, _ worksOn: [String]) async throws -> Void
    var updateSalonLanguage: (_ id: String, _ language: String) async throws -> Void
    var deleteSalon: (_ id: String) async throws -> Void
    // Status History
    var fetchStatusHistory: (_ salonId: String) async throws -> [StatusHistoryEntry] = { _ in [] }
    var fetchLatestStatusEntry: (_ salonId: String) async throws -> StatusHistoryEntry? = { _ in nil }
    var addStatusHistoryEntry: (_ salonId: String, _ status: SalonStatus, _ note: String, _ createdBy: String, _ date: Date, _ userLocation: Location?) async throws -> Void
    var updateStatusEntryNote: (_ salonId: String, _ entryId: String, _ note: String) async throws -> Void
    var deleteStatusHistoryEntry: (_ salonId: String, _ entryId: String) async throws -> Void
    // Users
    var fetchAllUsers: () async throws -> [AppUser] = { [] }
    var fetchUserActivity: (_ userId: String) async throws -> [UserActivityEntry] = { _ in [] }
    var deleteActivityEntry: (_ entry: UserActivityEntry) async throws -> Void
    // Plans
    var fetchActivePlan: () async throws -> Plan? = { nil }
    var fetchAllPlans: () async throws -> [Plan] = { [] }
    var savePlan: (_ plan: Plan) async throws -> Plan = { _ in throw NSError() }
    var deletePlan: (_ id: String) async throws -> Void
    var fetchDefaultPlan: () async throws -> DefaultPlan? = { nil }
    // Plan History
    var fetchPlanHistory: (_ userId: String) async throws -> [UserPlanHistoryEntry] = { _ in [] }
    var setPlanForAllUsers: (_ plan: Plan) async throws -> Void
    // Promos
    var fetchPromoCategories: () async throws -> [String] = { [] }
    var fetchPromos: () async throws -> [PromoOffer] = { [] }
    var savePromo: (_ promo: PromoOffer) async throws -> PromoOffer = { _ in throw NSError() }
    var activatePromo: (_ id: String, _ validFrom: Date, _ validTo: Date) async throws -> PromoOffer = { _, _, _ in throw FirebaseError.missingId }
    var deactivatePromo: (_ id: String) async throws -> PromoOffer = { _ in throw FirebaseError.missingId }
    var deletePromo: (_ id: String) async throws -> Void
    // Tags
    var loadWorksOnTags: () async -> [WorksOnTag] = { [] }
    var loadBundleCodes: () async -> Set<String> = { [] }
    // Barcode
    var lookupBarcodeArticle: (_ code: String) async throws -> String? = { _ in nil }
}

extension FirebaseClient: DependencyKey {
    static var liveValue: Self {
        MainActor.assumeIsolated {
            let s = FirebaseService.shared
            return Self(
                fetchSalons: { try await s.fetchSalons() },
                fetchAllSalons: { try await s.fetchAllSalons() },
                updateSalonStatus: { id, status, _, _ in try await s.updateSalonStatus(salonId: id, status: status) },
                updateSalonNotes: { id, notes in try await s.updateSalonNotes(salonId: id, notes: notes) },
                updateSalonLeadTemp: { id, temp in try await s.updateSalonLeadTemp(salonId: id, leadTemp: temp) },
                updateSalonWorksOn: { id, tags in try await s.updateSalonWorksOn(salonId: id, worksOn: tags) },
                updateSalonLanguage: { id, lang in try await s.updateSalonLanguage(salonId: id, language: lang) },
                deleteSalon: { id in try await s.deleteSalon(salonId: id) },
                fetchStatusHistory: { id in try await s.fetchStatusHistory(salonId: id) },
                fetchLatestStatusEntry: { id in try await s.fetchLatestStatusEntry(salonId: id) },
                addStatusHistoryEntry: { id, status, note, by, date, location in
                    try await s.addStatusHistoryEntry(salonId: id, status: status, note: note, createdBy: by, date: date, userLocation: location)
                },
                updateStatusEntryNote: { id, entryId, note in
                    try await s.updateStatusEntryNote(salonId: id, entryId: entryId, note: note)
                },
                deleteStatusHistoryEntry: { id, entryId in
                    try await s.deleteStatusHistoryEntry(salonId: id, entryId: entryId)
                },
                fetchAllUsers: { try await s.fetchAllUsers() },
                fetchUserActivity: { userId in try await s.fetchUserActivity(userId: userId) },
                deleteActivityEntry: { entry in
                    try await s.deleteStatusHistoryEntry(salonId: entry.salonId, entryId: entry.id)
                },
                fetchActivePlan: { try await s.fetchActivePlan() },
                fetchAllPlans: { try await s.fetchAllPlans() },
                savePlan: { plan in try await s.savePlan(plan) },
                deletePlan: { id in try await s.deletePlan(id: id) },
                fetchDefaultPlan: { try await s.fetchDefaultPlan() },
                fetchPlanHistory: { userId in try await s.fetchPlanHistory(userId: userId) },
                setPlanForAllUsers: { plan in try await s.setPlanForAllUsers(plan: plan) },
                fetchPromoCategories: { try await s.fetchPromoCategories() },
                fetchPromos: { try await s.fetchPromos() },
                savePromo: { promo in try await s.savePromo(promo) },
                activatePromo: { id, vf, vt in try await s.activatePromo(id: id, validFrom: vf, validTo: vt) },
                deactivatePromo: { id in try await s.deactivatePromo(id: id) },
                deletePromo: { id in try await s.deletePromo(id: id) },
                loadWorksOnTags: { await s.loadWorksOnTags() },
                loadBundleCodes: { await s.loadBundleCodes() },
                lookupBarcodeArticle: { code in try await s.lookupBarcodeArticle(code) }
            )
        }
    }
}

extension DependencyValues {
    nonisolated var firebaseClient: FirebaseClient {
        get { self[FirebaseClient.self] }
        set { self[FirebaseClient.self] = newValue }
    }
}
