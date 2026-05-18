// FILE: unic-ios/Features/SalonForm/SalonFormFeature.swift

import ComposableArchitecture
import Foundation
import SwiftUI

/// TCA feature managing the create/edit salon form including validation, dirty-state tracking, and Firebase persistence.
@Reducer
struct SalonFormFeature {

    // MARK: - State

    /// Observable state shared between the create and edit flows.
    @ObservableState
    struct State: Equatable {
        // Fields
        var name: String = ""
        var city: String = ""
        var address: String = ""
        var phone: String = ""
        /// Instagram handle without the leading `@` or URL prefix.
        var instagram: String = ""
        var website: String = ""
        var facebook: String = ""
        var notes: String = ""
        var status: SalonStatus = .new
        var selectedLanguage: String = "cs"
        var selectedLeadTemp: LeadTemp? = nil
        var selectedWorksOn: [String] = []

        // Meta
        /// `true` when editing an existing salon; `false` for creation.
        var isEdit: Bool = false
        var isSaving: Bool = false
        /// Tags available for the "Works On" multi-select.
        var availableTags: [WorksOnTag] = []
        var errorMessage: String? = nil
        var showDiscardAlert: Bool = false

        // Reference to the original salon when editing
        var originalSalonId: String? = nil
        /// Snapshot of the salon at load time, used for dirty-state comparison.
        var originalSalon: Salon? = nil

        // MARK: Computed

        /// `true` when the name field contains at least one non-whitespace character.
        var isValid: Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// `true` when any field has changed from its original value (or any field is non-empty in create mode).
        var isDirty: Bool {
            guard let original = originalSalon else {
                let hasText = !name.isEmpty || !address.isEmpty || !phone.isEmpty
                    || !instagram.isEmpty || !website.isEmpty || !facebook.isEmpty || !notes.isEmpty
                return hasText || !selectedWorksOn.isEmpty || selectedLeadTemp != nil
            }
            let origInstagram = Self.normalizedInstagram(original.contacts?.instagram?.value ?? "")
            let contactsChanged = phone != (original.contacts?.phone?.value ?? "")
                || instagram != origInstagram
                || website != (original.contacts?.website?.value ?? "")
                || facebook != (original.contacts?.facebook?.value ?? "")
            let basicChanged = name != original.name
                || address != (original.address ?? "")
                || notes != (original.notes ?? "")
            let crmChanged = selectedLanguage != (original.language ?? "cs")
                || selectedLeadTemp != original.leadTempEnum
                || selectedWorksOn != (original.worksOn ?? [])
            return basicChanged || contactsChanged || crmChanged
        }

        // MARK: Init

        init() { }

        init(salon: Salon) {
            self.isEdit = true
            self.originalSalon = salon
            self.originalSalonId = salon.salonId
            self.name = salon.name
            self.city = salon.city ?? ""
            self.address = salon.address ?? ""
            self.phone = salon.contacts?.phone?.value ?? ""
            self.instagram = Self.normalizedInstagram(salon.contacts?.instagram?.value ?? "")
            self.website = salon.contacts?.website?.value ?? ""
            self.facebook = salon.contacts?.facebook?.value ?? ""
            self.notes = salon.notes ?? ""
            self.status = salon.statusEnum
            self.selectedLanguage = salon.language ?? "cs"
            self.selectedLeadTemp = salon.leadTempEnum
            self.selectedWorksOn = salon.worksOn ?? []
        }

        /// Strips common Instagram URL prefixes and trailing slashes/`@` symbols from a raw string.
        /// - Parameter raw: The raw Instagram URL or handle to normalise.
        /// - Returns: A bare handle string such as `"mysalon"`.
        static func normalizedInstagram(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "https://www.instagram.com/", with: "")
                .replacingOccurrences(of: "https://instagram.com/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/@"))
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case tagsLoaded([WorksOnTag])
        case saveTapped
        case saveSucceeded(Salon)
        case saveFailed(String)
        case requestDismiss
        case forceDiscard
        case dismissDiscardAlert
    }

    // MARK: - Dependencies

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth
    @Dependency(\.dismiss) var dismiss

    // MARK: - Body

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {

            case .onLoad:
                let firebase = firebase
                return .run { [firebase] send in
                    let tags = await firebase.loadWorksOnTags()
                    await send(.tagsLoaded(tags))
                }

            case let .tagsLoaded(tags):
                state.availableTags = tags
                return .none

            case .saveTapped:
                let trimmedName = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return .none }
                state.isSaving = true
                let originalSalon = state.originalSalon
                let city = state.city
                let address = state.address
                let phone = state.phone
                let instagram = state.instagram
                let website = state.website
                let facebook = state.facebook
                let notes = state.notes
                let selectedLanguage = state.selectedLanguage
                let selectedLeadTemp = state.selectedLeadTemp
                let selectedWorksOn = state.selectedWorksOn
                let createdBy = auth.currentUser()?.id
                let dismiss = dismiss

                return .run { [dismiss] send in
                    do {
                        let result: Salon
                        if let existing = originalSalon {
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
                                createdBy: createdBy
                            )
                        }
                        await send(.saveSucceeded(result))
                        await dismiss()
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case let .saveSucceeded(salon):
                state.isSaving = false
                _ = salon // parent handles this action
                return .none

            case let .saveFailed(message):
                state.isSaving = false
                state.errorMessage = message
                return .none

            case .requestDismiss:
                if state.isDirty {
                    state.showDiscardAlert = true
                } else {
                    return .run { _ in await dismiss() }
                }
                return .none

            case .forceDiscard:
                state.showDiscardAlert = false
                return .run { _ in await dismiss() }

            case .dismissDiscardAlert:
                state.showDiscardAlert = false
                return .none

            case .binding:
                return .none
            }
        }
    }
}

private extension String {
    /// Returns the trimmed string, or `nil` if the result would be empty.
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - SalonFormView

/// Modal form for creating or editing a salon, with sections for basic info, contacts, CRM fields, and notes.
struct SalonFormView: View {
    @Bindable var store: StoreOf<SalonFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(String.section_main) {
                    TextField(String.salon_name_placeholder, text: $store.name)
                }

                Section(
                    header: Text(String.location),
                    footer: Text(String.address_hint)
                ) {
                    TextField(String.address_label, text: $store.address)
                }

                Section(String.section_contacts) {
                    TextField(String.phone_label, text: $store.phone)
                        .keyboardType(.phonePad)

                    HStack(spacing: 4) {
                        Text("@").foregroundColor(.secondary)
                        TextField("instagram", text: $store.instagram)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    TextField(String.website, text: $store.website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Facebook URL", text: $store.facebook)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("CRM") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String.language_label)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("", selection: $store.selectedLanguage) {
                            Text("🇺🇦").tag("uk")
                            Text("🇷🇺").tag("ru")
                            Text("🇨🇿").tag("cs")
                            Text("🇬🇧").tag("en")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text(String.lead_temp_label).foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(LeadTemp.allCases, id: \.self) { temp in
                                LeadTempBadge(temp: temp, isSelected: store.selectedLeadTemp == temp)
                                    .onTapGesture {
                                        store.selectedLeadTemp = store.selectedLeadTemp == temp ? nil : temp
                                    }
                            }
                        }
                    }
                }

                Section(String.works_on_label) {
                    WorksOnTagEditor(selectedTags: $store.selectedWorksOn)
                        .buttonStyle(.borderless)
                }

                Section(String.section_notes) {
                    TextField(String.notes_placeholder, text: $store.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String.add_salon)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { store.send(.requestDismiss) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.send(.saveTapped) } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!store.isValid || store.isSaving)
                }
            }
            .task { store.send(.onLoad) }
            .interactiveDismissDisabled(store.isDirty)
            .overlay {
                if store.isSaving {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .alert(String.error, isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .alert(String.discard_changes, isPresented: $store.showDiscardAlert) {
                Button(String.discard, role: .destructive) { store.send(.forceDiscard) }
                Button(String.cancel, role: .cancel) { store.send(.dismissDiscardAlert) }
            }
        }
    }
}
