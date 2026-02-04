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

    init(salon: Salon, onSalonUpdated: @escaping (Salon) -> Void, onSalonDeleted: @escaping () -> Void) {
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
                locationSection

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
        .sheet(isPresented: $viewModel.showAddStatus) {
            AddStatusSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showStatusHistory) {
            StatusHistorySheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Видалити салон?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Видалити", role: .destructive) {
                viewModel.deleteSalon()
                dismiss()
            }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("Ця дія незворотна. Салон \"\(salon.displayName)\" буде видалено назавжди.")
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
                    title: "Зателефонувати",
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
                        Label("Скопіювати номер", systemImage: "doc.on.doc")
                    }

                    Button {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Зателефонувати", systemImage: "phone.fill")
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
                    title: "Сайт",
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
                SectionHeader(title: "Локація")

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
            SectionHeader(title: "Статус")

            VStack(spacing: 0) {
                // Current Status
                HStack {
                    Text("Поточний:")
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
                        Text("Історія змін")
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

            VStack(spacing: 16) {
                // Lead Temp
                HStack {
                    HStack(spacing: 4) {
                        Text("Lead Temp:")
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

                    HStack(spacing: 8) {
                        ForEach(LeadTemp.allCases, id: \.self) { temp in
                            LeadTempBadge(
                                temp: temp,
                                isSelected: viewModel.selectedLeadTemp == temp
                            )
                        }
                    }
                }

                // Enrichment Status
                if let enrichmentStatus = salon.enrichmentStatus {
                    HStack {
                        Text("Збагачення:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(enrichmentStatus)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(role: .destructive) {
            viewModel.showDeleteConfirmation = true
        } label: {
            HStack {
                Spacer()
                Label("Видалити салон", systemImage: "trash")
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
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
    @State private var selectedStatus: SalonStatus
    @State private var note: String = ""
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SalonDetailViewModel) {
        self.viewModel = viewModel
        _selectedStatus = State(initialValue: viewModel.currentStatus)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Новий статус") {
                    Picker("Статус", selection: $selectedStatus) {
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

                Section("Нотатка (опційно)") {
                    TextField("Додати коментар...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Додати статус")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        viewModel.addStatusEntry(status: selectedStatus, note: note)
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
        }
    }
}

// MARK: - Status History Sheet

struct StatusHistorySheet: View {
    @ObservedObject var viewModel: SalonDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingHistory {
                    ProgressView("Завантаження...")
                        .frame(maxHeight: .infinity)
                } else if viewModel.statusHistory.isEmpty {
                    ContentUnavailableView(
                        "Немає історії",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Історія статусів поки порожня")
                    )
                } else {
                    List {
                        ForEach(viewModel.statusHistory) { entry in
                            StatusHistoryRow(entry: entry)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let entry = viewModel.statusHistory[index]
                                viewModel.deleteStatusEntry(entry)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Історія статусів")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.loadStatusHistory()
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
        case .A: return "A — Гарячий"
        case .B: return "B — Теплий"
        case .C: return "C — Холодний"
        }
    }

    var description: String {
        switch self {
        case .A:
            return "Високий пріоритет. Салон має Instagram, сайт, контакти та спеціалізується на колоруванні/нарощуванні."
        case .B:
            return "Середній пріоритет. Салон має деякі контакти або часткову спеціалізацію."
        case .C:
            return "Низький пріоритет. Мало контактної інформації або невідповідна спеціалізація (барбершоп, дитячі)."
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
                    Text("Lead Temp — автоматична оцінка пріоритетності салону на основі наявної інформації.")
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
                        Text("Як рахується оцінка")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ScoringRow(title: "Instagram", points: "+3")
                            ScoringRow(title: "Сайт", points: "+2")
                            ScoringRow(title: "Телефон", points: "+1")
                            ScoringRow(title: "Email", points: "+1")
                            ScoringRow(title: "Google Maps дані", points: "+1")
                            ScoringRow(title: "Колорування/Balayage", points: "+2-4")
                            ScoringRow(title: "Нарощування", points: "+2")
                            ScoringRow(title: "Барбершоп", points: "-2", isNegative: true)
                            ScoringRow(title: "Тільки діти", points: "-1", isNegative: true)
                        }

                        Text("A ≥ 7 балів  •  B ≥ 4 балів  •  C < 4 балів")
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
                    Button("Готово") {
                        dismiss()
                    }
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
                nextStep: nil,
                source: nil,
                enrichmentStatus: "enriched",
                enrichmentBatch: "001",
                googlePlacesTypes: ["hair_care", "beauty_salon", "establishment"]
            ),
            onSalonUpdated: { _ in },
            onSalonDeleted: { }
        )
    }
}
