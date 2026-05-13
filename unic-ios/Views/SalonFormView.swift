import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class SalonFormViewModel: ObservableObject {
    @Published var name: String
    @Published var city: String
    @Published var address: String
    @Published var phone: String
    @Published var instagram: String
    @Published var website: String
    @Published var facebook: String
    @Published var notes: String
    @Published var selectedLanguage: String
    @Published var selectedLeadTemp: LeadTemp?
    @Published var selectedWorksOn: [String]

    @Published private(set) var isSaving = false
    @Published var showAlert = false
    @Published private(set) var alertMessage = ""
    @Published var showLeadTempInfo = false
    @Published var showDiscardAlert = false

    let existingSalon: Salon?
    private let onSaved: (Salon) -> Void
    private let onDismiss: () -> Void

    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var isDirty: Bool {
        guard let s = existingSalon else {
            let hasText = !name.isEmpty || !address.isEmpty || !phone.isEmpty
                || !instagram.isEmpty || !website.isEmpty || !facebook.isEmpty || !notes.isEmpty
            return hasText || !selectedWorksOn.isEmpty || selectedLeadTemp != nil
        }
        let origInstagram = normalizedInstagram(s.contacts?.instagram?.value ?? "")
        let contactsChanged = phone != (s.contacts?.phone?.value ?? "")
            || instagram != origInstagram
            || website != (s.contacts?.website?.value ?? "")
            || facebook != (s.contacts?.facebook?.value ?? "")
        let basicChanged = name != s.name || address != (s.address ?? "") || notes != (s.notes ?? "")
        let crmChanged = selectedLanguage != (s.language ?? "cs")
            || selectedLeadTemp != s.leadTempEnum
            || selectedWorksOn != (s.worksOn ?? [])
        return basicChanged || contactsChanged || crmChanged
    }

    init(existingSalon: Salon? = nil, onSaved: @escaping (Salon) -> Void, onDismiss: @escaping () -> Void) {
        self.existingSalon = existingSalon
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        name             = existingSalon?.name ?? ""
        city             = existingSalon?.city ?? ""
        address          = existingSalon?.address ?? ""
        phone            = existingSalon?.contacts?.phone?.value ?? ""
        instagram        = normalizedInstagram(existingSalon?.contacts?.instagram?.value ?? "")
        website          = existingSalon?.contacts?.website?.value ?? ""
        facebook         = existingSalon?.contacts?.facebook?.value ?? ""
        notes            = existingSalon?.notes ?? ""
        selectedLanguage = existingSalon?.language ?? "cs"
        selectedLeadTemp = existingSalon?.leadTempEnum
        selectedWorksOn  = existingSalon?.worksOn ?? []
    }

    func requestDismiss() {
        if isDirty { showDiscardAlert = true } else { onDismiss() }
    }

    func forceDiscard() { onDismiss() }

    func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result: Salon
            if let existing = existingSalon {
                result = try await FirebaseService.shared.updateSalonBasicInfo(
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
                    leadTemp: selectedLeadTemp,
                    worksOn: selectedWorksOn,
                    previousAddress: existing.address,
                    previousCity: existing.city
                )
            } else {
                result = try await FirebaseService.shared.createSalon(
                    name: trimmedName,
                    city: city.trimmedOrNil,
                    address: address.trimmedOrNil,
                    phone: phone.trimmedOrNil,
                    instagram: instagram.trimmedOrNil,
                    website: website.trimmedOrNil,
                    facebook: facebook.trimmedOrNil,
                    language: selectedLanguage,
                    worksOn: selectedWorksOn,
                    leadTemp: selectedLeadTemp,
                    notes: notes.trimmedOrNil,
                    createdBy: AuthService.shared.currentUser?.id
                )
            }
            onSaved(result)
            onDismiss()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

private func normalizedInstagram(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "https://www.instagram.com/", with: "")
        .replacingOccurrences(of: "https://instagram.com/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/@"))
}

// MARK: - View

struct SalonFormScreen: View {
    @ObservedObject var viewModel: SalonFormViewModel
    @ObservedObject private var firebaseService = FirebaseService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(String.section_main) {
                    TextField(String.salon_name_placeholder, text: $viewModel.name)
                }

                Section(
                    header: Text(String.location),
                    footer: Text(String.address_hint)
                ) {
                    TextField(String.address_label, text: $viewModel.address)
                }

                Section(String.section_contacts) {
                    TextField(String.phone_label, text: $viewModel.phone)
                        .keyboardType(.phonePad)

                    HStack(spacing: 4) {
                        Text("@").foregroundColor(.secondary)
                        TextField("instagram", text: $viewModel.instagram)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    TextField(String.website, text: $viewModel.website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Facebook URL", text: $viewModel.facebook)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("CRM") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("language_label")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("", selection: $viewModel.selectedLanguage) {
                            Text("🇺🇦").tag("uk")
                            Text("🇷🇺").tag("ru")
                            Text("🇨🇿").tag("cs")
                            Text("🇬🇧").tag("en")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("lead_temp_label")
                            .foregroundColor(.secondary)
                        Button { viewModel.showLeadTempInfo = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(LeadTemp.allCases, id: \.self) { temp in
                                LeadTempBadge(temp: temp, isSelected: viewModel.selectedLeadTemp == temp)
                                    .onTapGesture {
                                        viewModel.selectedLeadTemp = viewModel.selectedLeadTemp == temp ? nil : temp
                                    }
                            }
                        }
                    }
                }

                Section(String.works_on_label) {
                    WorksOnTagEditor(selectedTags: $viewModel.selectedWorksOn)
                        .buttonStyle(.borderless)
                }

                Section(String.section_notes) {
                    TextField(String.notes_placeholder, text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: viewModel.existingSalon == nil ? "add_salon" : "edit_salon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { viewModel.requestDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await viewModel.save() } } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .task {
                if firebaseService.worksOnTags.isEmpty {
                    await firebaseService.loadWorksOnTags()
                }
            }
            .interactiveDismissDisabled(viewModel.isDirty)
            .overlay {
                if viewModel.isSaving {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .alert(String.error, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
            .alert(String.discard_changes, isPresented: $viewModel.showDiscardAlert) {
                Button(String.discard, role: .destructive) { viewModel.forceDiscard() }
                Button(String.cancel, role: .cancel) {}
            }
            .sheet(isPresented: $viewModel.showLeadTempInfo) {
                LeadTempInfoView(isPresented: $viewModel.showLeadTempInfo)
            }
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}
