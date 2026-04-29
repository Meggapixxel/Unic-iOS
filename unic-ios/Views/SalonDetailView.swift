//
//  SalonDetailView.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import SwiftUI
import MapKit
import IdentifiedCollections

struct SalonDetailView: View {
    @StateObject private var viewModel: SalonDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared

    private let showMap: Bool

    init(salon: Salon, showMap: Bool = true, onSalonUpdated: @escaping (Salon) -> Void, onSalonDeleted: @escaping () -> Void) {
        self.showMap = showMap
        _viewModel = StateObject(wrappedValue: SalonDetailViewModel(
            salon: salon,
            onSalonUpdated: onSalonUpdated,
            onSalonDeleted: onSalonDeleted
        ))
    }

    private var salon: Salon { viewModel.salon }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Info
                infoSection

                // Quick Actions
                quickActionsSection

                // Location
                if showMap { locationSection }

                // Status Section
                statusSection

                // CRM Section
                crmSection

                // Delete Section
                deleteSection
            }
            .padding()
        }
        .navigationTitle(salon.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if auth.isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showEditSalon = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showEditSalon) {
            SalonFormView(salon: salon) { updated in
                viewModel.salon = updated
                viewModel.onSalonUpdated(updated)
            }
        }
        .overlay {
            if viewModel.isSaving {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .sheet(isPresented: $viewModel.showLeadTempInfo) {
            LeadTempInfoView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showSalonCategoryInfo) {
            SalonCategoryInfoView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showAddStatus) {
            AddStatusSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showStatusHistory) {
            StatusHistorySheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "delete_salon_question",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("delete", role: .destructive) {
                viewModel.deleteSalon()
                dismiss()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("delete_confirmation \(salon.displayName)")
        }
        .task {
            viewModel.loadLatestStatusEntry()
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private var infoSection: some View {
        if let category = salon.categoryName {
            Text(category)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            if let phone = salon.phoneNumber {
                ActionButton(
                    title: String(localized: "call"),
                    icon: "phone.fill",
                    color: .green
                ) {
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }
                .contextMenu {
                    Text(phone)
                        .font(.headline)

                    Button {
                        UIPasteboard.general.string = phone
                    } label: {
                        Label("copy_number", systemImage: "doc.on.doc")
                    }

                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("call", systemImage: "phone.fill")
                    }
                }
            }

            if let instagram = salon.contacts?.instagram?.value,
               let url = URL(string: instagram) {
                ActionButton(
                    title: "Instagram",
                    icon: "camera.fill",
                    color: .purple
                ) {
                    UIApplication.shared.open(url)
                }
            }

            if let facebook = salon.contacts?.facebook?.value,
               let url = URL(string: facebook) {
                ActionButton(
                    title: "Facebook",
                    icon: "hand.thumbsup.fill",
                    color: .blue
                ) {
                    UIApplication.shared.open(url)
                }
            }

            if let url = salon.websiteURL {
                ActionButton(
                    title: String(localized: "website"),
                    icon: "globe",
                    color: .orange
                ) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
        let hasLocation = salon.coordinate != nil || salon.address != nil

        if hasLocation {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "location"))

                VStack(spacing: 0) {
                    // Map
                    if let coordinate = salon.coordinate {
                        NavigationLink {
                            SalonFullMapView(salon: salon)
                        } label: {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            ))) {
                                Marker(salon.displayName, coordinate: coordinate)
                                    .tint(salon.statusEnum.color)
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

                    // Address
                    if let address = salon.address {
                        if salon.coordinate != nil {
                            Divider()
                        }

                        Button {
                            UIPasteboard.general.string = address
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                Text(address)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Coordinates
                    if let location = salon.maps?.location {
                        Divider()

                        let coordString = String(format: "%.6f, %.6f", location.lat, location.lng)

                        Button {
                            UIPasteboard.general.string = coordString
                        } label: {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(.blue)
                                Text(coordString)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
            SectionHeader(title: String(localized: "status"))

            VStack(spacing: 0) {
                // Current Status
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("current_status")
                            .foregroundColor(.secondary)

                        Spacer()

                        StatusBadge(status: viewModel.currentStatus)

                        Button {
                            viewModel.showAddStatus = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                    }

                    if let note = viewModel.latestStatusEntry?.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()

                Divider()
                    .padding(.horizontal)

                // History Button
                Button {
                    viewModel.showStatusHistory = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                        Text("change_history")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                // Lead Temp
                HStack {
                    HStack(spacing: 4) {
                        Text("lead_temp_label")
                            .foregroundColor(.secondary)
                        Button {
                            viewModel.showLeadTempInfo = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if let temp = salon.leadTempEnum {
                        LeadTempBadge(temp: temp, isSelected: true)
                    } else {
                        Text("—").foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider().padding(.horizontal)

                // Salon Category
                HStack {
                    HStack(spacing: 4) {
                        Text("salon_category_label")
                            .foregroundColor(.secondary)
                        Button {
                            viewModel.showSalonCategoryInfo = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if let cat = salon.salonCategoryEnum {
                        SalonCategoryBadge(category: cat, isSelected: true)
                    } else {
                        Text("—").foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider().padding(.horizontal)

                // Language
                HStack {
                    Text("language_label")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(languageLabel(salon.language ?? "cs"))
                        .foregroundColor(.primary)
                }
                .padding()

                // Works On
                if let worksOn = salon.worksOn, !worksOn.isEmpty {
                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("works_on_label")
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(worksOn, id: \.self) { tagId in
                                let name = FirebaseService.shared.worksOnTags.first { $0.id == tagId }?.name ?? tagId
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }

                // Enrichment
                if let enrichmentStatus = salon.enrichmentStatus {
                    Divider().padding(.horizontal)
                    HStack {
                        Text("enrichment")
                            .foregroundColor(.secondary)
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

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "uk": return "🇺🇦"
        case "ru": return "🇷🇺"
        case "en": return "🇬🇧"
        default:   return "🇨🇿"
        }
    }

    // MARK: - Delete Section

    @ViewBuilder
    private var deleteSection: some View {
        if auth.isAdmin {
            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("delete_salon", systemImage: "trash")
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(12)
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
    }
}

// MARK: - Status History Row

struct StatusHistoryRow: View {
    let entry: StatusHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(entry.statusEnum.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.statusEnum.displayName)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let by = entry.createdBy {
                    Text(by)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Add Status Sheet

struct AddStatusSheet: View {
    @ObservedObject var viewModel: SalonDetailViewModel
    @ObservedObject private var flexiBee = FlexiBeeService.shared
    @State private var selectedStatus: SalonStatus
    @State private var note: String = ""
    @State private var selectedArticleCodes: [String] = []
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SalonDetailViewModel) {
        self.viewModel = viewModel
        _selectedStatus = State(initialValue: viewModel.currentStatus)
    }

    private var stockTagItems: [TagItem] {
        flexiBee.stockWithPrices.map {
            TagItem(id: $0.kod, name: $0.nazev.isEmpty ? $0.kod : "\($0.kod) — \($0.nazev)")
        }
    }

    private var effectiveNote: String? {
        let articleText = selectedArticleCodes.isEmpty ? "" : selectedArticleCodes.joined(separator: ", ")
        let parts = [articleText, note].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("new_status") {
                    Picker("status_picker", selection: $selectedStatus) {
                        ForEach(SalonStatus.allCases, id: \.self) { status in
                            HStack {
                                Circle()
                                    .fill(status.color)
                                    .frame(width: 10, height: 10)
                                Text(status.displayName)
                            }
                            .tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if selectedStatus == .testDrive {
                    Section(String(localized: "articles_label")) {
                        TagEditor(
                            selectedIds: $selectedArticleCodes,
                            availableTags: stockTagItems,
                            placeholder: "articles_search",
                            canAddNew: false,
                            onAddNew: nil
                        )
                    }
                }

                Section("note_optional") {
                    TextField(String(localized: "add_comment"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("add_status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let createdBy = AuthService.shared.currentUser?.id
                        viewModel.addStatusEntry(status: selectedStatus, note: effectiveNote, createdBy: createdBy)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .task {
                await flexiBee.loadIfNeeded()
            }
        }
    }
}

// MARK: - Status History Sheet

struct StatusHistorySheet: View {
    @ObservedObject var viewModel: SalonDetailViewModel
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingHistory {
                    ProgressView("loading")
                        .frame(maxHeight: .infinity)
                } else if viewModel.statusHistory.isEmpty {
                    ContentUnavailableView(
                        "no_history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("history_empty")
                    )
                } else {
                    List {
                        ForEach(viewModel.statusHistory) { entry in
                            StatusHistoryRow(entry: entry)
                        }
                        .onDelete(perform: auth.isAdmin ? { indexSet in
                            for index in indexSet {
                                let entry = viewModel.statusHistory[index]
                                viewModel.deleteStatusEntry(entry)
                            }
                        } : nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("status_history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
        .task {
            viewModel.loadStatusHistory()
        }
    }
}

// MARK: - Salon Category Badge

struct SalonCategoryBadge: View {
    let category: SalonCategory
    let isSelected: Bool

    var body: some View {
        Text(category.rawValue)
            .font(.subheadline.bold())
            .frame(width: 32, height: 32)
            .background(isSelected ? category.color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(8)
    }
}

extension SalonCategory {
    var color: Color {
        switch self {
        case .A: return .green
        case .B: return .teal
        case .C: return Color(.systemGray2)
        }
    }

    var title: String {
        switch self {
        case .A: return String(localized: "salon_category_a")
        case .B: return String(localized: "salon_category_b")
        case .C: return String(localized: "salon_category_c")
        }
    }
}

// MARK: - Lead Temp Badge

struct LeadTempBadge: View {
    let temp: LeadTemp
    let isSelected: Bool

    var body: some View {
        Text(temp.rawValue)
            .font(.subheadline.bold())
            .frame(width: 32, height: 32)
            .background(isSelected ? temp.color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(8)
    }
}

extension LeadTemp {
    var color: Color {
        switch self {
        case .A: return .red
        case .B: return .orange
        case .C: return .blue
        }
    }

    var title: String {
        switch self {
        case .A: return String(localized: "lead_temp_a")
        case .B: return String(localized: "lead_temp_b")
        case .C: return String(localized: "lead_temp_c")
        }
    }

    var description: String {
        switch self {
        case .A: return String(localized: "lead_temp_a_desc")
        case .B: return String(localized: "lead_temp_b_desc")
        case .C: return String(localized: "lead_temp_c_desc")
        }
    }
}

// MARK: - Lead Temp Info Sheet

struct LeadTempInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Intro
                    Text("lead_temp_intro")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Ratings
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(LeadTemp.allCases, id: \.self) { temp in
                            HStack(alignment: .top, spacing: 12) {
                                Text(temp.rawValue)
                                    .font(.title2.bold())
                                    .frame(width: 40, height: 40)
                                    .background(temp.color)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(temp.title)
                                        .font(.headline)
                                    Text(temp.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    // Scoring explanation
                    VStack(alignment: .leading, spacing: 12) {
                        Text("scoring_header")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ScoringRow(title: "Instagram", points: "+3")
                            ScoringRow(title: String(localized: "scoring_website"), points: "+2")
                            ScoringRow(title: String(localized: "scoring_phone"), points: "+1")
                            ScoringRow(title: "Email", points: "+1")
                            ScoringRow(title: String(localized: "scoring_google_maps"), points: "+1")
                            ScoringRow(title: String(localized: "scoring_coloring"), points: "+2-4")
                            ScoringRow(title: String(localized: "scoring_extensions"), points: "+2")
                            ScoringRow(title: String(localized: "scoring_barbershop"), points: "-2", isNegative: true)
                            ScoringRow(title: String(localized: "scoring_kids"), points: "-1", isNegative: true)
                        }

                        Text("scoring_thresholds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("Lead Temp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

struct ScoringRow: View {
    let title: String
    let points: String
    var isNegative: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(points)
                .font(.subheadline.bold())
                .foregroundColor(isNegative ? .red : .green)
        }
    }
}

// MARK: - Salon Category Info Sheet

struct SalonCategoryInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("salon_category_intro")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(SalonCategory.allCases, id: \.self) { cat in
                            HStack(alignment: .top, spacing: 12) {
                                Text(cat.rawValue)
                                    .font(.title2.bold())
                                    .frame(width: 40, height: 40)
                                    .background(cat.color)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cat.title)
                                        .font(.headline)
                                    Text(cat.categoryDescription)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("salon_category_criteria_header")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ScoringRow(title: String(localized: "salon_category_criteria_aesthetics"), points: "★★★")
                            ScoringRow(title: String(localized: "salon_category_criteria_seats"), points: "★★★")
                            ScoringRow(title: String(localized: "salon_category_criteria_equipment"), points: "★★")
                            ScoringRow(title: String(localized: "salon_category_criteria_location"), points: "★★")
                            ScoringRow(title: String(localized: "salon_category_criteria_services"), points: "★★")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("salon_category_info_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }
}

extension SalonCategory {
    var categoryDescription: String {
        switch self {
        case .A: return String(localized: "salon_category_a_desc")
        case .B: return String(localized: "salon_category_b_desc")
        case .C: return String(localized: "salon_category_c_desc")
        }
    }
}

#Preview {
    NavigationStack {
        SalonDetailView(
            salon: Salon(
                salonId: "test",
                name: "Test Salon",
                city: "Prague",
                address: "Test Address 123",
                categoryName: "Hair Salon",
                category: ["hair"],
                tags: [],
                maps: Maps(provider: "google", mapsUrl: "https://maps.google.com", placeId: "test", location: Location(lat: 50.0, lng: 14.4), source: "excel", confidence: 1.0),
                contacts: Contacts(
                    website: Contact(value: "https://test.com", alt: nil, foundFrom: "excel", isPrimary: true, confidence: nil),
                    phone: Contact(value: "+420123456789", alt: nil, foundFrom: "excel", isPrimary: true, confidence: nil),
                    email: nil,
                    instagram: Contact(value: "https://instagram.com/test", alt: nil, foundFrom: "website", isPrimary: true, confidence: 0.95),
                    facebook: nil,
                    tiktok: nil
                ),
                leadTemp: "A",
                status: "new",
                ownerDriven: nil,
                notes: "Test notes",
                worksOn: ["Колорування", "Нарощування"],
                language: "cs",
                nextStep: nil,
                salonCategory: "A",
                source: nil,
                enrichmentStatus: "enriched",
                enrichmentBatch: "001",
                googlePlacesTypes: ["hair_care", "beauty_salon", "establishment"],
                createdBy: nil,
                latestStatusEntry: nil
            ),
            onSalonUpdated: { _ in },
            onSalonDeleted: { }
        )
    }
}
