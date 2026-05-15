// FILE: unic-ios/Features/SalonDetail/SalonDetailFeature.swift

import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
struct SalonDetailFeature {

    // MARK: - Destination

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

    @ObservableState
    struct State: Equatable {
        var salon: Salon
        var statusHistory: IdentifiedArrayOf<StatusHistoryEntry> = []
        var latestEntry: StatusHistoryEntry?
        var isLoadingHistory = false
        var isSaving = false
        var shouldDismiss = false
        var canEdit: Bool = false
        var canDelete: Bool = false
        var canEditHistory: Bool = false
        @Presents var destination: Destination.State?

        init(salon: Salon) {
            self.salon = salon
            self.latestEntry = salon.latestStatusEntry
        }

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

@Reducer
struct AddStatusFeature {
    @ObservableState
    struct State: Equatable {
        var salonId: String
        var currentStatus: SalonStatus
        var currentUserId: String
        var selectedStatus: SalonStatus
        var note: String = ""
        var selectedDate: Date
        var minScheduledDate: Date
        var isSaving = false
        var locationError: Bool = false

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
        case saveTapped
        case entryAdded(StatusHistoryEntry, updatedSalon: Salon?)
        case failed(String)
        case locationErrorDismissed
        case cancelTapped
    }

    @Dependency(\.firebaseClient) var firebase
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.date) var date
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .saveTapped:
                guard !state.isSaving else { return .none }
                state.isSaving = true
                let salonId = state.salonId
                let selectedStatus = state.selectedStatus
                let note = state.note
                let noteOrNil: String? = note.isEmpty ? nil : note
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
                            salonId, selectedStatus, note, createdBy, scheduledDate ?? date(), userLocation
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

@Reducer
struct StatusHistoryFeature {
    @ObservableState
    struct State: Equatable {
        var salonId: String
        var history: IdentifiedArrayOf<StatusHistoryEntry> = []
        var isLoading: Bool = false
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
        case loadHistory
        case historyLoaded([StatusHistoryEntry])
        case updateNote(String, entryId: String)
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
