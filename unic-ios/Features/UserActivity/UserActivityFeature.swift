import ComposableArchitecture
import Foundation

/// TCA feature for the user-activity screen, supporting day-by-day and custom date-range views with per-status statistics.
@Reducer
struct UserActivityFeature {
    /// Observable state for the user activity screen.
    @ObservableState
    struct State: Equatable {
        /// The user whose activity is being displayed.
        var user: AppUser
        /// All status history entries belonging to the user, sorted newest-first.
        var entries: [UserActivityEntry] = []
        var isLoading = false
        var error: String?
        /// Whether the date control shows a single-day picker or a custom range selector.
        var groupMode: GroupMode = .day
        /// The day selected in single-day mode.
        var selectedDate: Date
        /// Start of the custom date range.
        var customStart: Date
        /// End of the custom date range.
        var customEnd: Date
        /// The maximum selectable date (today at load time).
        var maxDate: Date
        var canDeleteActivity = false

        /// Controls how dates are grouped in the activity view.
        enum GroupMode: String, CaseIterable, Equatable {
            case day, custom
        }

        init(user: AppUser) {
            @Dependency(\.date) var date
            let now = date()
            self.user = user
            self.maxDate = now
            self.selectedDate = now
            self.customEnd = now
            self.customStart = Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now
        }

        /// Entries that fall within the currently active date selection (single day or custom range).
        var filteredEntries: [UserActivityEntry] {
            let cal = Calendar(identifier: .gregorian)
            switch groupMode {
            case .day:
                return entries.filter { cal.isDate($0.timestamp, inSameDayAs: selectedDate) }
            case .custom:
                let start = cal.startOfDay(for: customStart)
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd
                return entries.filter { $0.timestamp >= start && $0.timestamp < end }
            }
        }

        /// Count of filtered entries grouped by their salon status.
        var filteredStatusCounts: [SalonStatus: Int] {
            Dictionary(grouping: filteredEntries, by: \.status).mapValues(\.count)
        }

        /// Filtered entries grouped by calendar day (start-of-day key), sorted newest-first.
        var filteredEntriesByDay: [(Date, [UserActivityEntry])] {
            let cal = Calendar(identifier: .gregorian)
            let grouped = Dictionary(grouping: filteredEntries) { cal.startOfDay(for: $0.timestamp) }
            return grouped.sorted { $0.key > $1.key }
        }

        /// Human-readable label for the currently selected day (e.g. "Today", "Yesterday", "3 May").
        var dayLabel: String {
            let cal = Calendar(identifier: .gregorian)
            if cal.isDateInToday(selectedDate) { return "Today" }
            if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMM"
            return fmt.string(from: selectedDate)
        }
    }

    @CasePathable
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case loaded([UserActivityEntry])
        case failed(String)
        case deleteTapped(UserActivityEntry)
        case deleteConfirmed(UserActivityEntry)
        case navigateToPlans
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .navigateToPlans:
                return .none

            case .onLoad:
                state.canDeleteActivity = auth.canDeleteActivity()
                state.isLoading = true
                let userId = state.user.id
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        let entries = try await firebase.fetchUserActivity(userId)
                        await send(.loaded(entries))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            case .loaded(let entries):
                state.isLoading = false
                state.entries = entries.sorted { $0.timestamp > $1.timestamp }
                return .none
            case .failed(let msg):
                state.isLoading = false
                state.error = msg
                return .none
            case .deleteTapped:
                return .none
            case .deleteConfirmed(let entry):
                state.entries.removeAll { $0.id == entry.id }
                let firebase = firebase
                return .run { [firebase] send in
                    do {
                        try await firebase.deleteActivityEntry(entry)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
}
        }
    }
}
