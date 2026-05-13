// FILE: unic-ios/Features/SalonDetail/SalonDetailView.swift

import ComposableArchitecture
import SwiftUI
import MapKit

struct SalonDetailView: View {
    @Bindable var store: StoreOf<SalonDetailFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                quickActionsSection
                locationSection
                statusSection
                crmSection
                notesSection
                deleteSection
                adminSection
            }
            .padding()
        }
        .navigationTitle(store.salon.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if store.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.editTapped) } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .task { store.send(.onLoad) }
        // MARK: - Form Sheet
        .sheet(
            item: $store.scope(state: \.destination?.form, action: \.destination.form)
        ) { formStore in
            SalonFormView(store: formStore)
        }
        // MARK: - Add Status Sheet
        .sheet(
            item: $store.scope(state: \.destination?.addStatus, action: \.destination.addStatus)
        ) { addStatusStore in
            AddStatusView(store: addStatusStore)
        }
        // MARK: - Status History Sheet
        .sheet(
            item: $store.scope(state: \.destination?.statusHistory, action: \.destination.statusHistory)
        ) { historyStore in
            StatusHistoryView(store: historyStore)
        }
        // MARK: - Delete Confirmation
        .confirmationDialog(
            String.delete_salon_question,
            isPresented: Binding(
                get: {
                    if case .deleteConfirmation = store.destination { return true }
                    return false
                },
                set: { if !$0 { store.send(.destination(.dismiss)) } }
            ),
            titleVisibility: .visible
        ) {
            Button(String.delete, role: .destructive) {
                store.send(.deleteConfirmed)
            }
            Button(String.cancel, role: .cancel) {
                store.send(.destination(.dismiss))
            }
        } message: {
            Text(String.delete_confirmation(store.salon.displayName))
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            if let phone = store.salon.phoneNumber {
                ActionButton(title: String.call, icon: "phone.fill", color: .green) {
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = phone
                    } label: {
                        Label(String.copy_number, systemImage: "doc.on.doc")
                    }
                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(String.call, systemImage: "phone.fill")
                    }
                }
            }

            if let instagram = store.salon.contacts?.instagram?.value, let url = URL(string: instagram) {
                ActionButton(title: "Instagram", icon: "camera.fill", color: .purple) {
                    UIApplication.shared.open(url)
                }
            }

            if let facebook = store.salon.contacts?.facebook?.value, let url = URL(string: facebook) {
                ActionButton(title: "Facebook", icon: "hand.thumbsup.fill", color: .blue) {
                    UIApplication.shared.open(url)
                }
            }

            if let url = store.salon.websiteURL {
                ActionButton(title: String.website, icon: "globe", color: .orange) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
        let hasLocation = store.salon.coordinate != nil || store.salon.address != nil
        if hasLocation {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String.location)

                VStack(spacing: 0) {
                    if let coordinate = store.salon.coordinate {
                        NavigationLink {
                            SalonFullMapScreen(salon: store.salon)
                        } label: {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            ))) {
                                Marker(store.salon.displayName, coordinate: coordinate)
                                    .tint(store.salon.statusEnum.color)
                            }
                            .frame(height: 150)
                            .allowsHitTesting(false)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)
                                    .padding(8)
                            }
                        }
                    }

                    if let address = store.salon.address {
                        if store.salon.coordinate != nil { Divider() }

                        HStack {
                            Button {
                                UIPasteboard.general.string = address
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").foregroundColor(.red)
                                    Text(address)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.secondary)
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                openNavigation(
                                    coordinate: store.salon.coordinate,
                                    address: address,
                                    name: store.salon.displayName
                                )
                            } label: {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 12)
                        }
                    }

                    if let location = store.salon.maps?.location {
                        Divider()
                        let coordString = String(format: "%.6f, %.6f", location.lat, location.lng)
                        Button {
                            UIPasteboard.general.string = coordString
                        } label: {
                            HStack {
                                Image(systemName: "location.circle.fill").foregroundColor(.blue)
                                Text(coordString)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.secondary)
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String.status)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String.current_status).foregroundColor(.secondary)
                        Spacer()
                        StatusBadge(status: store.currentStatus)
                        Button {
                            store.send(.addStatusTapped)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                    }

                    if let note = store.latestEntry?.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(String.status_update_hint)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding()

                Divider().padding(.horizontal)

                Button {
                    store.send(.openStatusHistory)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                        Text(String.change_history)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - CRM Section

    private var crmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "CRM")

            VStack(spacing: 0) {
                HStack {
                    Text(String.lead_temp_label).foregroundColor(.secondary)
                    Spacer()
                    if let temp = store.salon.leadTempEnum {
                        LeadTempBadge(temp: temp, isSelected: true)
                    } else {
                        Text("—").foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider().padding(.horizontal)

                HStack {
                    Text(String.language_label).foregroundColor(.secondary)
                    Spacer()
                    Text(languageFlag(store.salon.language ?? "cs"))
                }
                .padding()

                if let worksOn = store.salon.worksOn, !worksOn.isEmpty {
                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String.works_on_label).foregroundColor(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(worksOn, id: \.self) { tagId in
                                let name = FirebaseService.shared.worksOnTags.first { $0.id == tagId }?.name ?? tagId
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                }

                if let enrichmentStatus = store.salon.enrichmentStatus {
                    Divider().padding(.horizontal)
                    HStack {
                        Text(String.enrichment).foregroundColor(.secondary)
                        Spacer()
                        Text(enrichmentStatus)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .padding()
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private var notesSection: some View {
        if let notes = store.salon.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String.section_notes)
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Delete Section

    @ViewBuilder
    private var deleteSection: some View {
        if store.canDelete {
            Button(role: .destructive) {
                store.send(.deleteTapped)
            } label: {
                HStack {
                    Spacer()
                    if store.isSaving {
                        ProgressView().tint(.red)
                    } else {
                        Label(String.delete_salon, systemImage: "trash")
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .disabled(store.isSaving)
        }
    }

    // MARK: - Admin Section

    @ViewBuilder
    private var adminSection: some View {
        if store.canEditHistory { // isAdmin check
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "ADMIN")
                HStack {
                    Text("ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.salon.salonId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Helpers

    private func languageFlag(_ code: String) -> String {
        switch code {
        case "uk": return "🇺🇦"
        case "ru": return "🇷🇺"
        case "en": return "🇬🇧"
        default:   return "🇨🇿"
        }
    }

    private func openNavigation(coordinate: CLLocationCoordinate2D?, address: String, name: String) {
        if let coord = coordinate {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let googleUrl = URL(string: "comgooglemaps://?daddr=\(coord.latitude),\(coord.longitude)&directionsmode=driving")
            let appleUrl = URL(string: "maps://?daddr=\(coord.latitude),\(coord.longitude)&q=\(encoded)")
            if let google = googleUrl, UIApplication.shared.canOpenURL(google) {
                UIApplication.shared.open(google)
            } else if let apple = appleUrl {
                UIApplication.shared.open(apple)
            }
        } else if let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let appleUrl = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(appleUrl)
        }
    }
}

// MARK: - AddStatusView

struct AddStatusView: View {
    @Bindable var store: StoreOf<AddStatusFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(String.new_status) {
                    Picker(String.status_picker, selection: $store.selectedStatus) {
                        ForEach(SalonStatus.allCases, id: \.self) { status in
                            HStack {
                                Circle().fill(status.color).frame(width: 10, height: 10)
                                Text(status.displayName)
                            }
                            .tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if store.selectedStatus == .demoScheduled {
                    Section(String.demo_date_label) {
                        DatePicker(
                            "",
                            selection: $store.selectedDate,
                            in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                    }
                }

                Section(String.note_optional) {
                    TextField(String.add_comment, text: $store.note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String.add_status)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { store.send(.cancelTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.send(.saveTapped) } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(store.isSaving)
                }
            }
            .overlay {
                if store.isSaving {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - StatusHistoryView

struct StatusHistoryView: View {
    @Bindable var store: StoreOf<StatusHistoryFeature>
    @State private var editingEntry: StatusHistoryEntry?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView(String.loading).frame(maxHeight: .infinity)
                } else if store.history.isEmpty {
                    ContentUnavailableView(
                        String.no_history,
                        systemImage: "clock.arrow.circlepath",
                        description: Text(String.history_empty)
                    )
                } else {
                    List {
                        ForEach(store.history) { entry in
                            StatusHistoryRow(entry: entry)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if store.canEditHistory {
                                        Button {
                                            editingEntry = entry
                                        } label: {
                                            Label(String.edit_note, systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                        .onDelete(perform: store.canEditHistory ? { indexSet in
                            for index in indexSet {
                                if let id = store.history[index].id {
                                    store.send(.deleteEntry(id))
                                }
                            }
                        } : nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String.status_history)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $editingEntry) { entry in
            EditNoteSheet(
                entry: entry,
                isPresented: Binding(
                    get: { editingEntry != nil },
                    set: { if !$0 { editingEntry = nil } }
                )
            ) { newNote in
                if let id = entry.id, let note = newNote {
                    store.send(.updateNote(note, entryId: id))
                }
            }
        }
        .task { store.send(.loadHistory) }
    }
}
