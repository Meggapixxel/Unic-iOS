// FILE: unic-ios/Features/SalonDetail/SalonDetailFeature.swift

import ComposableArchitecture
import Foundation
import IdentifiedCollections

/// TCA feature managing the salon detail screen: status changes, form editing, history, and deletion.
@Reducer
struct SalonDetailFeature {

    // MARK: - Destination

    /// All modal presentations that can be shown from the salon detail screen.
    @Reducer
    struct Destination {
        @ObservableState
        enum State: Equatable {
            case form(SalonFormFeature.State)
            case addStatus(AddStatusFeature.State)
            case statusHistory(StatusHistoryFeature.State)
            case deleteConfirmation
        }

        @CasePathable
        enum Action {
            case form(SalonFormFeature.Action)
            case addStatus(AddStatusFeature.Action)
            case statusHistory(StatusHistoryFeature.Action)
            case deleteConfirmation
        }

        var body: some Reducer<State, Action> {
            Reduce { _, _ in .none }
                .ifCaseLet(\.form, action: \.form) { SalonFormFeature() }
                .ifCaseLet(\.addStatus, action: \.addStatus) { AddStatusFeature() }
                .ifCaseLet(\.statusHistory, action: \.statusHistory) { StatusHistoryFeature() }
        }
    }

    // MARK: - State

    /// Observable state for the salon detail screen.
    @ObservableState
    struct State: Equatable {
        /// The salon being displayed; updated in place when edits are saved.
        var salon: Salon
        /// Full status history loaded when the history sheet is opened.
        var statusHistory: IdentifiedArrayOf<StatusHistoryEntry> = []
        /// Most recent status history entry, shown inline on the detail screen.
        var latestEntry: StatusHistoryEntry?
        var isLoadingHistory = false
        var isSaving = false
        /// Set to `true` just before `@Dependency(\.dismiss)` is called so parent can react.
        var shouldDismiss = false
        var canEdit: Bool = false
        var canDelete: Bool = false
        /// `true` for admin users who may edit or delete status history entries.
        var canEditHistory: Bool = false
        @Presents var destination: Destination.State?

        init(salon: Salon) {
            self.salon = salon
            self.latestEntry = salon.latestStatusEntry
        }

        /// The salon's current pipeline status derived from the stored value.
        var currentStatus: SalonStatus { salon.statusEnum }
    }

    // MARK: - Action

    enum Action {
        case onLoad
        case historyLoaded([StatusHistoryEntry])
        case latestEntryLoaded(StatusHistoryEntry?)
        case editTapped
        case deleteTapped
        case deleteConfirmed
        case deleteFinished
        case addStatusTapped
        case statusAdded(StatusHistoryEntry)
        case updateNote(String, entryId: String)
        case deleteEntry(String)
        case salonUpdated(Salon)
        case destination(PresentationAction<Destination.Action>)
        case failed(String)
        case openStatusHistory
    }

    // MARK: - Dependencies

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.authClient) var auth
    @Dependency(\.dismiss) var dismiss

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            case .onLoad:
                state.canEdit = auth.canEditSalon()
                state.canDelete = auth.canDeleteSalon()
                state.canEditHistory = auth.isAdmin()
                let firebase = firebase
                return .run { [firebase, salonId = state.salon.salonId] send in
                    do {
                        let entry = try await firebase.fetchLatestStatusEntry(salonId)
                        await send(.latestEntryLoaded(entry))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .latestEntryLoaded(entry):
                state.latestEntry = entry
                return .none

            case let .historyLoaded(history):
                state.isLoadingHistory = false
                state.statusHistory = IdentifiedArrayOf(
                    uniqueElements: history.filter { $0.id != nil }
                )
                state.latestEntry = state.statusHistory.first
                // Propagate to open statusHistory destination if any
                if case var .statusHistory(histState) = state.destination {
                    histState.history = state.statusHistory
                    histState.isLoading = false
                    state.destination = .statusHistory(histState)
                }
                return .none

            case .editTapped:
                state.destination = .form(SalonFormFeature.State(salon: state.salon))
                return .none

            case .deleteTapped:
                state.destination = .deleteConfirmation
                return .none

            case .deleteConfirmed:
                state.isSaving = true
                state.destination = nil
                let firebase = firebase
                return .run { [firebase, salonId = state.salon.salonId] send in
                    do {
                        try await firebase.deleteSalon(salonId)
                        await send(.deleteFinished)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .deleteFinished:
                state.isSaving = false
                state.shouldDismiss = true
                return .run { _ in await dismiss() }

            case .addStatusTapped:
                guard let user = auth.currentUser() else { return .none }
                state.destination = .addStatus(
                    AddStatusFeature.State(
                        salonId: state.salon.salonId,
                        currentStatus: state.salon.statusEnum,
                        currentUserId: user.id
                    )
                )
                return .none

            case let .statusAdded(entry):
                if entry.id != nil {
                    state.statusHistory.insert(entry, at: 0)
                }
                state.latestEntry = entry
                state.salon.status = entry.status
                return .none

            case let .updateNote(note, entryId: entryId):
                let firebase = firebase
                return .run { [firebase, salonId = state.salon.salonId] send in
                    do {
                        try await firebase.updateStatusEntryNote(salonId, entryId, note)
                        let history = try await firebase.fetchStatusHistory(salonId)
                        await send(.historyLoaded(history))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .deleteEntry(entryId):
                state.statusHistory.remove(id: entryId)
                let firebase = firebase
                return .run { [firebase, salonId = state.salon.salonId] send in
                    do {
                        try await firebase.deleteStatusHistoryEntry(salonId, entryId)
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case let .salonUpdated(salon):
                state.isSaving = false
                state.salon = salon
                state.destination = nil
                return .none

            case let .failed(message):
                state.isSaving = false
                state.isLoadingHistory = false
                _ = message
                return .none

            case .openStatusHistory:
                state.destination = .statusHistory(
                    StatusHistoryFeature.State(
                        salonId: state.salon.salonId,
                        history: state.statusHistory,
                        isLoading: state.statusHistory.isEmpty,
                        canEditHistory: state.canEditHistory
                    )
                )
                if state.statusHistory.isEmpty {
                    return loadHistory(salonId: state.salon.salonId)
                }
                return .none

            // MARK: Destination forwarding

            case let .destination(.presented(.form(.saveSucceeded(salon)))):
                return .send(.salonUpdated(salon))

            case let .destination(.presented(.addStatus(.entryAdded(entry, _)))):
                return .send(.statusAdded(entry))

            case let .destination(.presented(.statusHistory(.updateNote(note, entryId: entryId)))):
                return .send(.updateNote(note, entryId: entryId))

            case let .destination(.presented(.statusHistory(.deleteEntry(entryId)))):
                return .send(.deleteEntry(entryId))

            case .destination(.presented(.statusHistory(.loadHistory))):
                state.isLoadingHistory = true
                if case var .statusHistory(histState) = state.destination {
                    histState.isLoading = true
                    state.destination = .statusHistory(histState)
                }
                return loadHistory(salonId: state.salon.salonId)

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) { Destination() }
    }

    /// Fetches the full status history for a salon and dispatches the result.
    /// - Parameter salonId: The Firestore document ID of the salon.
    /// - Returns: An effect sending `.historyLoaded` on success or `.failed` on error.
    private func loadHistory(salonId: String) -> Effect<Action> {
        let firebase = firebase
        return .run { [firebase] send in
            do {
                let history = try await firebase.fetchStatusHistory(salonId)
                await send(.historyLoaded(history))
            } catch {
                await send(.failed(error.localizedDescription))
            }
        }
    }
}

// MARK: - AddStatusFeature

/// TCA feature for the "Add Status" sheet, including location capture and optional article / demo-date selection.
@Reducer
struct AddStatusFeature {
    /// Observable state for the add-status form.
    @ObservableState
    struct State: Equatable {
        var salonId: String
        /// The salon's status at the time the sheet was opened.
        var currentStatus: SalonStatus
        var currentUserId: String
        /// Status chosen by the user in the picker.
        var selectedStatus: SalonStatus
        var note: String = ""
        /// Scheduled demo date, used only when `selectedStatus == .demoScheduled`.
        var selectedDate: Date
        /// Earliest selectable demo date (tomorrow).
        var minScheduledDate: Date
        var isSaving = false
        /// `true` when location could not be obtained; triggers an alert.
        var locationError: Bool = false
        /// Article codes chosen for a test-drive entry.
        var selectedArticleCodes: [String] = []
        /// Stock items used to populate the article picker.
        var stockItems: [FlexiBeeStockItem] = []

        init(salonId: String, currentStatus: SalonStatus, currentUserId: String) {
            @Dependency(\.date) var date
            let now = date()
            self.salonId = salonId
            self.currentStatus = currentStatus
            self.currentUserId = currentUserId
            self.selectedStatus = currentStatus
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            self.minScheduledDate = tomorrow
            self.selectedDate = tomorrow
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onLoad
        case saveTapped
        /// Sent after the entry has been persisted; `updatedSalon` may carry a refreshed salon.
        case entryAdded(StatusHistoryEntry, updatedSalon: Salon?)
        case failed(String)
        case locationErrorDismissed
        case cancelTapped
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.flexiBeeClient) var flexiBeeClient
    @Dependency(\.date) var date
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onLoad:
                state.stockItems = Array(flexiBeeClient.stockWithPrices())
                return .none

            case .saveTapped:
                guard !state.isSaving else { return .none }
                state.isSaving = true
                let salonId = state.salonId
                let selectedStatus = state.selectedStatus
                let articleText = selectedStatus == .testDrive && !state.selectedArticleCodes.isEmpty
                    ? state.selectedArticleCodes.joined(separator: ", ")
                    : nil
                let notePart = state.note.isEmpty ? nil : state.note
                let effectiveNote = [articleText, notePart].compactMap { $0 }.joined(separator: "\n")
                let noteOrNil: String? = effectiveNote.isEmpty ? nil : effectiveNote
                let createdBy = state.currentUserId
                let scheduledDate: Date? = selectedStatus == .demoScheduled ? state.selectedDate : nil
                let firebase = firebase
                let locationClient = locationClient
                return .run { [firebase, date] send in
                    let userLocation = await locationClient.fetchLocation()
                    guard userLocation != nil else {
                        await send(.failed(String(localized: "location_unavailable")))
                        return
                    }
                    do {
                        try await firebase.addStatusHistoryEntry(
                            salonId, selectedStatus, effectiveNote, createdBy, scheduledDate ?? date(), userLocation
                        )
                        let history = try await firebase.fetchStatusHistory(salonId)
                        let entry = history.first ?? StatusHistoryEntry(
                            status: selectedStatus.rawValue,
                            note: noteOrNil,
                            timestamp: date(),
                            createdBy: createdBy,
                            date: scheduledDate,
                            userLocation: userLocation
                        )
                        await send(.entryAdded(entry, updatedSalon: nil))
                        await dismiss()
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }
            case .entryAdded:
                state.isSaving = false
                return .none
            case .failed(let msg):
                state.isSaving = false
                state.locationError = msg == String(localized: "location_unavailable")
                return .none
            case .locationErrorDismissed:
                state.locationError = false
                return .none
            case .cancelTapped:
                return .run { _ in await dismiss() }
            case .binding:
                return .none
            }
        }
    }
}

// MARK: - StatusHistoryFeature

/// Child feature that models the status history list; actual data loading is delegated to the parent via action forwarding.
@Reducer
struct StatusHistoryFeature {
    /// Observable state for the status history sheet.
    @ObservableState
    struct State: Equatable {
        var salonId: String
        /// Chronologically ordered status history entries.
        var history: IdentifiedArrayOf<StatusHistoryEntry> = []
        var isLoading: Bool = false
        /// `true` for admins who may edit or delete entries.
        var canEditHistory: Bool = false

        init(
            salonId: String,
            history: IdentifiedArrayOf<StatusHistoryEntry> = [],
            isLoading: Bool = false,
            canEditHistory: Bool = false
        ) {
            self.salonId = salonId
            self.history = history
            self.isLoading = isLoading
            self.canEditHistory = canEditHistory
        }
    }

    enum Action {
        /// Requests history to be loaded; actual fetch is handled by the parent reducer.
        case loadHistory
        case historyLoaded([StatusHistoryEntry])
        /// Requests a note update; handled by the parent reducer.
        case updateNote(String, entryId: String)
        /// Requests deletion of an entry; handled by the parent reducer.
        case deleteEntry(String)
        case failed(String)
    }

    @Dependency(\.authClient) var auth

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadHistory:
                state.isLoading = true
                state.canEditHistory = auth.isAdmin()
                return .none // loading is handled by parent via action forwarding
            case let .historyLoaded(entries):
                state.isLoading = false
                state.history = IdentifiedArrayOf(uniqueElements: entries.filter { $0.id != nil })
                return .none
            case .updateNote, .deleteEntry:
                return .none // handled by parent
            case .failed:
                state.isLoading = false
                return .none
            }
        }
    }
}
