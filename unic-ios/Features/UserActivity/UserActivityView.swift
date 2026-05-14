import ComposableArchitecture
import SwiftUI

struct UserActivityView: View {
    @Bindable var store: StoreOf<UserActivityFeature>

    var body: some View {
        List {
            Section {
                let counts = store.statusCounts
                if !counts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SalonStatus.allCases, id: \.self) { status in
                                if let count = counts[status] {
                                    VStack(spacing: 4) {
                                        Text("\(count)")
                                            .font(.title3.bold())
                                            .foregroundStyle(status.color)
                                        Text(status.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Picker(String.activity_group_day, selection: $store.groupMode) {
                Text(String.activity_group_day).tag(UserActivityFeature.State.GroupMode.day)
                Text(String.activity_group_week).tag(UserActivityFeature.State.GroupMode.week)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            let groups = store.groupMode == .day ? store.entriesByDay : store.entriesByWeek
            ForEach(groups, id: \.0) { title, entries in
                Section(title) {
                    ForEach(entries) { entry in
                        ActivityEntryRow(entry: entry)
                            .swipeActions(edge: .trailing) {
                                if store.canDeleteActivity {
                                    Button(role: .destructive) {
                                        store.send(.deleteConfirmed(entry))
                                    } label: {
                                        Label(String.delete, systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(store.user.fullName)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if store.isLoading { ProgressView() }
            else if store.entries.isEmpty && !store.isLoading {
                ContentUnavailableView(String.activity_empty, systemImage: "clock.arrow.circlepath")
            }
        }
        .task { store.send(.onLoad) }
    }
}

private struct ActivityEntryRow: View {
    let entry: UserActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.salonName).font(.subheadline)
                Spacer()
                Text(entry.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(entry.status.color)
            }
            if !(entry.note ?? "").isEmpty {
                Text(entry.note ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
