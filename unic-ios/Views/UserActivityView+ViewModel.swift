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

@MainActor
final class UserActivityViewModel: ObservableObject {
    @Published var entries: [UserActivityEntry] = []
    @Published var isLoading = false
    @Published var groupMode: ActivityGroupMode = .day

    private let service = FirebaseService.shared

    func load(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        entries = (try? await service.fetchUserActivity(userId: userId)) ?? []
        isLoading = false
    }

    func delete(_ entry: UserActivityEntry) async {
        try? await service.deleteStatusHistoryEntry(salonId: entry.salonId, entryId: entry.id)
        entries.removeAll { $0.id == entry.id }
    }

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
}
