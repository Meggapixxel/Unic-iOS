import ComposableArchitecture
import Foundation

@Reducer
struct UserActivityFeature {
    @ObservableState
    struct State: Equatable {
        var user: AppUser
        var entries: [UserActivityEntry] = []
        var isLoading = false
        var error: String?
        var groupMode: GroupMode = .day
        var canDeleteActivity = false

        enum GroupMode: String, CaseIterable, Equatable {
            case day, week
        }

        var statusCounts: [SalonStatus: Int] {
            Dictionary(grouping: entries, by: { $0.status }).mapValues(\.count)
        }

        var entriesByDay: [(String, [UserActivityEntry])] {
            let grouped = Dictionary(grouping: entries) { entry -> String in
                entry.timestamp.formatted(.dateTime.day().month(.abbreviated).year())
            }
            return grouped.sorted { $0.key > $1.key }
        }

        var entriesByWeek: [(String, [UserActivityEntry])] {
            let cal = Calendar.current
            let grouped = Dictionary(grouping: entries) { entry -> String in
                let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.timestamp)
                return "Week \(comps.weekOfYear ?? 0), \(comps.yearForWeekOfYear ?? 0)"
            }
            return grouped.sorted { $0.key > $1.key }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case loaded([UserActivityEntry])
        case failed(String)
        case deleteTapped(UserActivityEntry)
        case deleteConfirmed(UserActivityEntry)
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .onLoad:
                state.canDeleteActivity = auth.canDeleteActivity()
                state.isLoading = true
                let userId = state.user.id
                return .run { send in
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
                return .run { send in
                    do {
                        try await firebase.deleteActivityEntry(entry.id)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            }
        }
    }
}
