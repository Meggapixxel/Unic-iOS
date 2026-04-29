//
//  AddSalonView.swift
//  unic-ios
//

import SwiftUI

struct AddSalonView: View {
    @Environment(\.dismiss) private var dismiss

    // Main
    @State private var name = ""
    @State private var city = ""
    @State private var address = ""

    // Contacts
    @State private var phone = ""
    @State private var instagram = ""
    @State private var website = ""
    @State private var facebook = ""

    // CRM
    @State private var selectedLanguage = "cs"
    @State private var selectedCategory: SalonCategory? = nil
    @State private var selectedLeadTemp: LeadTemp? = nil
    @State private var selectedWorksOn: [String] = []

    // Notes
    @State private var notes = ""

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    let onSalonCreated: (Salon) -> Void

    private let service = FirebaseService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "section_main")) {
                    TextField(String(localized: "salon_name_placeholder"), text: $name)
                    TextField(String(localized: "city"), text: $city)
                    TextField(String(localized: "address_label"), text: $address)
                }

                Section(String(localized: "section_contacts")) {
                    TextField(String(localized: "phone_label"), text: $phone)
                        .keyboardType(.phonePad)

                    HStack(spacing: 4) {
                        Text("@")
                            .foregroundColor(.secondary)
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
                            Text("УКР").tag("uk")
                            Text("РУС").tag("ru")
                            Text("ЧЕХ").tag("cs")
                            Text("АНГ").tag("en")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("salon_category_label")
                            .foregroundColor(.secondary)
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
            .navigationTitle(String(localized: "add_salon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
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
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSaving = true

        Task {
            defer { isSaving = false }

            do {
                let salon = try await service.createSalon(
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
                    notes: notes.trimmedOrNil
                )
                onSalonCreated(salon)
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
