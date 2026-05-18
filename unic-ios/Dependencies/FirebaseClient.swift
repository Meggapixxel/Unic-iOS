import ComposableArchitecture
import Foundation

/// TCA dependency that exposes `FirebaseService` functionality to reducers via `@Dependency`.
/// Covers salons, status history, users, plans, promos, tags, and barcode lookups.
@DependencyClient
struct FirebaseClient: @unchecked Sendable {
    // Salons
    /// Fetches only the salons assigned to the current user.
    var fetchSalons: () async throws -> [Salon] = { [] }
    /// Fetches every salon in the Firestore collection regardless of assignment.
    var fetchAllSalons: () async throws -> [Salon] = { [] }
    /// Updates the status of a salon and records the change in the history subcollection.
    var updateSalonStatus: (_ id: String, _ status: SalonStatus, _ note: String, _ createdBy: String) async throws -> Void
    /// Persists free-text notes on a salon document.
    var updateSalonNotes: (_ id: String, _ notes: String) async throws -> Void
    /// Updates the lead temperature tag on a salon.
    var updateSalonLeadTemp: (_ id: String, _ temp: LeadTemp) async throws -> Void
    /// Replaces the `worksOn` product tags array on a salon.
    var updateSalonWorksOn: (_ id: String, _ worksOn: [String]) async throws -> Void
    /// Sets the preferred contact language for a salon.
    var updateSalonLanguage: (_ id: String, _ language: String) async throws -> Void
    /// Permanently deletes a salon document from Firestore.
    var deleteSalon: (_ id: String) async throws -> Void
    // Status History
    /// Fetches all status history entries for a salon, sorted by date.
    var fetchStatusHistory: (_ salonId: String) async throws -> [StatusHistoryEntry] = { _ in [] }
    /// Returns only the most recent status history entry for a salon.
    var fetchLatestStatusEntry: (_ salonId: String) async throws -> StatusHistoryEntry? = { _ in nil }
    /// Appends a new status history entry to a salon's subcollection.
    var addStatusHistoryEntry: (_ salonId: String, _ status: SalonStatus, _ note: String, _ createdBy: String, _ date: Date, _ userLocation: Location?) async throws -> Void
    /// Updates the note text of an existing history entry.
    var updateStatusEntryNote: (_ salonId: String, _ entryId: String, _ note: String) async throws -> Void
    /// Deletes a history entry from a salon's subcollection.
    var deleteStatusHistoryEntry: (_ salonId: String, _ entryId: String) async throws -> Void
    // Users
    /// Fetches all `AppUser` documents from Firestore.
    var fetchAllUsers: () async throws -> [AppUser] = { [] }
    /// Fetches the status-history activity entries authored by a specific user.
    var fetchUserActivity: (_ userId: String) async throws -> [UserActivityEntry] = { _ in [] }
    /// Deletes a user activity entry (which is a status history entry in a salon subcollection).
    var deleteActivityEntry: (_ entry: UserActivityEntry) async throws -> Void
    // Plans
    /// Returns the currently active sales plan for the signed-in user, or `nil`.
    var fetchActivePlan: () async throws -> Plan? = { nil }
    /// Fetches all plan documents from Firestore.
    var fetchAllPlans: () async throws -> [Plan] = { [] }
    /// Creates or updates a plan document and returns the saved plan with its Firestore ID.
    var savePlan: (_ plan: Plan) async throws -> Plan = { _ in throw NSError() }
    /// Permanently deletes a plan document by ID.
    var deletePlan: (_ id: String) async throws -> Void
    /// Returns the default plan template used when creating new user plans.
    var fetchDefaultPlan: () async throws -> DefaultPlan? = { nil }
    // Plan History
    /// Fetches the plan history subcollection for a given user ID.
    var fetchPlanHistory: (_ userId: String) async throws -> [UserPlanHistoryEntry] = { _ in [] }
    /// Writes the given plan into the history subcollection for all users.
    var setPlanForAllUsers: (_ plan: Plan) async throws -> Void
    // Promos
    /// Fetches the list of available promo category names.
    var fetchPromoCategories: () async throws -> [String] = { [] }
    /// Fetches all promo offer documents from Firestore.
    var fetchPromos: () async throws -> [PromoOffer] = { [] }
    /// Creates or updates a promo offer and returns the saved record.
    var savePromo: (_ promo: PromoOffer) async throws -> PromoOffer = { _ in throw NSError() }
    /// Activates a promo for a specific date range and returns the updated offer.
    var activatePromo: (_ id: String, _ validFrom: Date, _ validTo: Date) async throws -> PromoOffer = { _, _, _ in throw FirebaseError.missingId }
    /// Clears the validity window of a promo and returns the deactivated offer.
    var deactivatePromo: (_ id: String) async throws -> PromoOffer = { _ in throw FirebaseError.missingId }
    /// Permanently deletes a promo offer document.
    var deletePromo: (_ id: String) async throws -> Void
    // Tags
    /// Loads all `worksOn` product tags from Firestore.
    var loadWorksOnTags: () async -> [WorksOnTag] = { [] }
    /// Loads the set of known bundle product codes used for stock matching.
    var loadBundleCodes: () async -> Set<String> = { [] }
    // Barcode
    /// Looks up the FlexiBee article code for a given barcode string.
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
    /// The `FirebaseClient` dependency for use with `@Dependency(\.firebaseClient)`.
    nonisolated var firebaseClient: FirebaseClient {
        get { self[FirebaseClient.self] }
        set { self[FirebaseClient.self] = newValue }
    }
}
