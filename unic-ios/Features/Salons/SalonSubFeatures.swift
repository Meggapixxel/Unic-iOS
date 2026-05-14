// FILE: unic-ios/Features/Salons/SalonSubFeatures.swift
// Stub reducers that bridge TCA navigation to legacy ViewModel-based screens.
// Replace each stub with a full TCA reducer once the screen is migrated.

import ComposableArchitecture
import Foundation
import IdentifiedCollections

// MARK: - TestDriveFeature

@Reducer
struct TestDriveFeature {
    @ObservableState
    struct State: Equatable {
        var salons: IdentifiedArrayOf<Salon>
    }
    enum Action {
        case salonTapped(Salon)
    }
    var body: some Reducer<State, Action> { EmptyReducer() }
}

// MARK: - RoutePlannerFeature

@Reducer
struct RoutePlannerFeature {
    @ObservableState
    struct State: Equatable {
        var salons: IdentifiedArrayOf<Salon>
    }
    enum Action {}
    var body: some Reducer<State, Action> { EmptyReducer() }
}

