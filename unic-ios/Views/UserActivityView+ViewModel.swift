import SwiftUI
import Combine
import FirebaseFirestore

enum ActivityGroupMode: String, CaseIterable {
    case day  = "day"
    case week = "week"

    var displayName: String {
        switch self {
        case .day:  return String.activity_group_day
        case .week: return String.activity_group_week
        }
    }
}

/// Displays the status-change log for a single team member, grouped by day or week.
/// Entries are fetched via a Firestore collectionGroup query across all salon status-history subcollections.
@MainActor
final class UserActivityViewModel: ObservableObject {
    @Published var entries: [UserActivityEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var groupMode: ActivityGroupMode = .day

    private let service = FirebaseService.shared

    func load(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            entries = try await service.fetchUserActivity(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Soft delete: removes the Firestore subcollection entry and updates local state immediately
    /// so the UI doesn't wait for a re-fetch.
    func delete(_ entry: UserActivityEntry) async {
        do {
            try await service.deleteStatusHistoryEntry(salonId: entry.salonId, entryId: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Aggregated status breakdown for the summary bar at the top of the activity screen.
    var statusCounts: [(status: SalonStatus, count: Int)] {
        let grouped = Dictionary(grouping: entries) { $0.status }
        return SalonStatus.allCases
            .compactMap { s -> (SalonStatus, Int)? in
                let c = grouped[s]?.count ?? 0
                return c > 0 ? (s, c) : nil
            }
            .sorted { $0.1 > $1.1 }
    }

    var entriesByDay: [(key: Date, entries: [UserActivityEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.timestamp) }
        return grouped
            .map { (key: $0.key, entries: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.key > $1.key }
    }

    var entriesByWeek: [(key: Date, entries: [UserActivityEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            cal.dateInterval(of: .weekOfYear, for: entry.timestamp)?.start ?? entry.timestamp
        }
        return grouped
            .map { (key: $0.key, entries: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.key > $1.key }
    }

    // Per-week breakdown: "new" salons (first appearance) vs "old" (already seen before that week).
    var weeklyNewVsOld: [Date: (new: Int, old: Int)] {
        let cal = Calendar.current
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        var seenBefore: Set<String> = []
        var weekNew: [Date: Set<String>] = [:]
        var weekOld: [Date: Set<String>] = [:]

        for entry in sorted {
            let weekStart = cal.dateInterval(of: .weekOfYear, for: entry.timestamp)?.start ?? entry.timestamp
            if seenBefore.contains(entry.salonId) {
                weekOld[weekStart, default: []].insert(entry.salonId)
            } else {
                weekNew[weekStart, default: []].insert(entry.salonId)
                seenBefore.insert(entry.salonId)
            }
        }

        let allWeeks = Set(weekNew.keys).union(weekOld.keys)
        return Dictionary(uniqueKeysWithValues: allWeeks.map { week in
            (week, (new: weekNew[week]?.count ?? 0, old: weekOld[week]?.count ?? 0))
        })
    }
}
