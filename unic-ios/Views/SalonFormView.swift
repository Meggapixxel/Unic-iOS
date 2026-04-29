//
//  SalonFormView.swift
//  unic-ios
//

import SwiftUI

struct SalonFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var city: String
    @State private var address: String
    @State private var phone: String
    @State private var instagram: String
    @State private var website: String
    @State private var facebook: String
    @State private var notes: String

    @State private var selectedLanguage: String
    @State private var selectedCategory: SalonCategory?
    @State private var selectedLeadTemp: LeadTemp?
    @State private var selectedWorksOn: [String]

    @State private var createdBy: String = AppSettings.shared.currentUser
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showLeadTempInfo = false
    @State private var showSalonCategoryInfo = false
    @State private var showDiscardAlert = false

    private let existingSalon: Salon?
    private let service = FirebaseService.shared
    private let onSaved: (Salon) -> Void

    init(salon: Salon? = nil, onSaved: @escaping (Salon) -> Void) {
        self.existingSalon = salon
        self.onSaved = onSaved
        _name      = State(initialValue: salon?.name ?? "")
        _city      = State(initialValue: salon?.city ?? "")
        _address   = State(initialValue: salon?.address ?? "")
        _phone     = State(initialValue: salon?.contacts?.phone?.value ?? "")
        _instagram = State(initialValue: {
            (salon?.contacts?.instagram?.value ?? "")
                .replacingOccurrences(of: "https://www.instagram.com/", with: "")
                .replacingOccurrences(of: "https://instagram.com/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/@"))
        }())
        _website          = State(initialValue: salon?.contacts?.website?.value ?? "")
        _facebook         = State(initialValue: salon?.contacts?.facebook?.value ?? "")
        _notes            = State(initialValue: salon?.notes ?? "")
        _selectedLanguage = State(initialValue: salon?.language ?? "cs")
        _selectedCategory = State(initialValue: salon?.salonCategoryEnum)
        _selectedLeadTemp = State(initialValue: salon?.leadTempEnum)
        _selectedWorksOn  = State(initialValue: salon?.worksOn ?? [])
    }

    private var isDirty: Bool {
        guard let s = existingSalon else {
            let hasText = !name.isEmpty || !address.isEmpty || !phone.isEmpty
                || !instagram.isEmpty || !website.isEmpty || !facebook.isEmpty || !notes.isEmpty
            let hasCRM = !selectedWorksOn.isEmpty || selectedCategory != nil || selectedLeadTemp != nil
            return hasText || hasCRM
        }
        let origInstagram = (s.contacts?.instagram?.value ?? "")
            .replacingOccurrences(of: "https://www.instagram.com/", with: "")
            .replacingOccurrences(of: "https://instagram.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/@"))
        let contactsChanged = phone != (s.contacts?.phone?.value ?? "")
            || instagram != origInstagram
            || website != (s.contacts?.website?.value ?? "")
            || facebook != (s.contacts?.facebook?.value ?? "")
        let basicChanged = name != s.name || address != (s.address ?? "") || notes != (s.notes ?? "")
        let crmChanged = selectedLanguage != (s.language ?? "cs")
            || selectedCategory != s.salonCategoryEnum
            || selectedLeadTemp != s.leadTempEnum
            || selectedWorksOn != (s.worksOn ?? [])
        return basicChanged || contactsChanged || crmChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "section_main")) {
                    TextField(String(localized: "salon_name_placeholder"), text: $name)
                    if existingSalon == nil {
                        HStack {
                            Text(String(localized: "created_by_label"))
                                .foregroundColor(.secondary)
                            TextField("admin", text: $createdBy)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }

                Section(
                    header: Text(String(localized: "location")),
                    footer: Text(String(localized: "address_hint"))
                ) {
                    TextField(String(localized: "address_label"), text: $address)
                }

                Section(String(localized: "section_contacts")) {
                    TextField(String(localized: "phone_label"), text: $phone)
                        .keyboardType(.phonePad)

                    HStack(spacing: 4) {
                        Text("@").foregroundColor(.secondary)
                        TextField("instagram", text: $instagram)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    TextField(String(localized: "website"), text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Facebook URL", text: $facebook)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("CRM") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("language_label")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("", selection: $selectedLanguage) {
                            Text("🇺🇦").tag("uk")
                            Text("🇷🇺").tag("ru")
                            Text("🇨🇿").tag("cs")
                            Text("🇬🇧").tag("en")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("salon_category_label")
                            .foregroundColor(.secondary)
                        Button { showSalonCategoryInfo = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(SalonCategory.allCases, id: \.self) { cat in
                                SalonCategoryBadge(category: cat, isSelected: selectedCategory == cat)
                                    .onTapGesture {
                                        selectedCategory = selectedCategory == cat ? nil : cat
                                    }
                            }
                        }
                    }

                    HStack {
                        Text("lead_temp_label")
                            .foregroundColor(.secondary)
                        Button { showLeadTempInfo = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(LeadTemp.allCases, id: \.self) { temp in
                                LeadTempBadge(temp: temp, isSelected: selectedLeadTemp == temp)
                                    .onTapGesture {
                                        selectedLeadTemp = selectedLeadTemp == temp ? nil : temp
                                    }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("works_on_label")
                            .foregroundColor(.secondary)
                        WorksOnTagEditor(selectedTags: $selectedWorksOn)
                    }
                }

                Section(String(localized: "section_notes")) {
                    TextField(
                        String(localized: "notes_placeholder"),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: existingSalon == nil ? "add_salon" : "edit_salon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .alert(String(localized: "error"), isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert(String(localized: "discard_changes"), isPresented: $showDiscardAlert) {
                Button(String(localized: "discard"), role: .destructive) { dismiss() }
                Button(String(localized: "cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showLeadTempInfo) {
                LeadTempInfoView()
            }
            .sheet(isPresented: $showSalonCategoryInfo) {
                SalonCategoryInfoView()
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true

        Task {
            defer { isSaving = false }
            do {
                let result: Salon
                if let existing = existingSalon {
                    result = try await service.updateSalonBasicInfo(
                        salonId: existing.salonId,
                        name: trimmedName,
                        city: city.trimmedOrNil,
                        address: address.trimmedOrNil,
                        phone: phone.trimmedOrNil,
                        instagram: instagram.trimmedOrNil,
                        website: website.trimmedOrNil,
                        facebook: facebook.trimmedOrNil,
                        notes: notes.trimmedOrNil,
                        language: selectedLanguage,
                        salonCategory: selectedCategory,
                        leadTemp: selectedLeadTemp,
                        worksOn: selectedWorksOn,
                        previousAddress: existing.address,
                        previousCity: existing.city
                    )
                } else {
                    let resolvedCreatedBy = createdBy.trimmedOrNil ?? "admin"
                    AppSettings.shared.currentUser = resolvedCreatedBy
                    result = try await service.createSalon(
                        name: trimmedName,
                        city: city.trimmedOrNil,
                        address: address.trimmedOrNil,
                        phone: phone.trimmedOrNil,
                        instagram: instagram.trimmedOrNil,
                        website: website.trimmedOrNil,
                        facebook: facebook.trimmedOrNil,
                        language: selectedLanguage,
                        salonCategory: selectedCategory,
                        worksOn: selectedWorksOn,
                        leadTemp: selectedLeadTemp,
                        notes: notes.trimmedOrNil,
                        createdBy: resolvedCreatedBy
                    )
                }
                onSaved(result)
                dismiss()
            } catch {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
