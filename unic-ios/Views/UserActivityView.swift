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

struct UserActivityView: View {
    let user: AppUser
    @StateObject private var viewModel = UserActivityViewModel()
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        List {
            if !viewModel.statusCounts.isEmpty {
                Section(String.activity_statistics) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.statusCounts, id: \.status) { item in
                                VStack(spacing: 4) {
                                    Text("\(item.count)")
                                        .font(.title3.bold())
                                        .foregroundStyle(item.status.color)
                                    Text(item.status.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(minWidth: 64)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(item.status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }

            if viewModel.groupMode == .day {
                ForEach(viewModel.entriesByDay, id: \.key) { group in
                    Section(header: DayHeader(date: group.key, count: group.entries.count)) {
                        ForEach(group.entries) { entry in
                            ActivityRow(entry: entry)
                        }
                        .onDelete(perform: auth.canDeleteActivity ? { offsets in
                            let toDelete = offsets.map { group.entries[$0] }
                            Task { for e in toDelete { await viewModel.delete(e) } }
                        } : nil)
                    }
                }
            } else {
                ForEach(viewModel.entriesByWeek, id: \.key) { group in
                    Section(header: WeekHeader(weekStart: group.key, count: group.entries.count)) {
                        ForEach(group.entries) { entry in
                            ActivityRow(entry: entry, showDate: true)
                        }
                        .onDelete(perform: auth.canDeleteActivity ? { offsets in
                            let toDelete = offsets.map { group.entries[$0] }
                            Task { for e in toDelete { await viewModel.delete(e) } }
                        } : nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(user.fullName)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("", selection: $viewModel.groupMode) {
                ForEach(ActivityGroupMode.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .overlay {
            if !viewModel.isLoading && viewModel.entries.isEmpty {
                ContentUnavailableView(String.activity_empty, systemImage: "person.crop.circle.badge.clock")
            }
        }
        .task { await viewModel.load(userId: user.id) }
    }
}

// MARK: - Day Header

private struct DayHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
            Text("activity_actions \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return String.activity_today }
        if cal.isDateInYesterday(date) { return String.activity_yesterday }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}

// MARK: - Week Header

private struct WeekHeader: View {
    let weekStart: Date
    let count: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
            Text("activity_actions \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        let cal = Calendar.current
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let now = Date()

        if let interval = cal.dateInterval(of: .weekOfYear, for: now), interval.start == weekStart {
            return String.activity_this_week
        }
        if let interval = cal.dateInterval(of: .weekOfYear, for: cal.date(byAdding: .weekOfYear, value: -1, to: now)!),
           interval.start == weekStart {
            return String.activity_last_week
        }

        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd))"
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let entry: UserActivityEntry
    var showDate: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(entry.status.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.salonName)
                    .font(.callout)
                    .lineLimit(1)
                if let note = entry.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(entry.status.color)
                if showDate {
                    Text(entry.timestamp.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
