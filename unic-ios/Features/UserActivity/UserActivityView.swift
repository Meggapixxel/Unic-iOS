import ComposableArchitecture
import SwiftUI

struct UserActivityView: View {
    @Bindable var store: StoreOf<UserActivityFeature>

    var body: some View {
        List {
            // MARK: Mode picker + period navigation
            Section {
                Picker(String.activity_group_day, selection: $store.groupMode) {
                    Text(String.activity_group_day).tag(UserActivityFeature.State.GroupMode.day)
                    Text(String.activity_group_custom).tag(UserActivityFeature.State.GroupMode.custom)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if store.groupMode == .day {
                    DatePicker(String.activity_group_day, selection: $store.selectedDate, in: ...store.maxDate, displayedComponents: .date)
                } else {
                    DatePicker(String.activity_from, selection: $store.customStart, in: ...store.customEnd, displayedComponents: .date)
                    DatePicker(String.activity_to, selection: $store.customEnd, in: store.customStart...store.maxDate, displayedComponents: .date)
                }
            }

            // MARK: Stats for selected period
            let counts = store.filteredStatusCounts
            if !counts.isEmpty {
                Section {
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

            // MARK: Entries — always grouped by day
            ForEach(store.filteredEntriesByDay, id: \.0) { date, dayEntries in
                Section(date.formatted(.dateTime.weekday(.abbreviated).day().month())) {
                    ForEach(dayEntries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(store.user.fullName)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if store.isLoading {
                ProgressView()
            } else if store.filteredEntries.isEmpty && !store.isLoading && !store.entries.isEmpty {
                ContentUnavailableView(String.activity_no_data, systemImage: "calendar.badge.minus")
            } else if store.entries.isEmpty && !store.isLoading {
                ContentUnavailableView(String.activity_empty, systemImage: "clock.arrow.circlepath")
            }
        }
        .task { store.send(.onLoad) }
    }

    @ViewBuilder
    private func entryRow(_ entry: UserActivityEntry) -> some View {
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
