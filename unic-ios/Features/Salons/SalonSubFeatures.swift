// FILE: unic-ios/Features/Salons/SalonSubFeatures.swift
// Stub reducers that bridge TCA navigation to legacy ViewModel-based screens.
// Replace each stub with a full TCA reducer once the screen is migrated.

import ComposableArchitecture
import Foundation
import IdentifiedCollections

// MARK: - TestDriveFeature

/// Stub reducer bridging TCA navigation to the legacy test-drive ViewModel screen.
///
/// Holds the list of salons to display in the test-drive view. Has no async side effects of its own —
/// it is an empty reducer (`EmptyReducer`). The single action `.salonTapped(_)` is intercepted by
/// the parent `SalonsFeature`, which pushes a `SalonDetailFeature` onto the navigation stack.
/// Replace with a full TCA reducer once the screen is migrated away from its ViewModel.
@Reducer
struct TestDriveFeature {
    /// Holds the salons displayed in the test-drive list.
    @ObservableState
    struct State: Equatable {
        var salons: IdentifiedArrayOf<Salon>
    }
    enum Action {
        /// Sent when the user taps a salon row; handled by the parent `SalonsFeature` to push detail.
        case salonTapped(Salon)
    }
    var body: some Reducer<State, Action> { EmptyReducer() }
}

// MARK: - RoutePlannerFeature

/// Stub reducer bridging TCA navigation to the legacy route-planner ViewModel screen.
///
/// Holds the ordered list of salons passed into the route planner. Has no actions and no async
/// side effects (`EmptyReducer`). The view owned by this feature is still ViewModel-based.
/// Replace with a full TCA reducer once the screen is migrated.
@Reducer
struct RoutePlannerFeature {
    /// Holds the salons passed to the route planner for ordering.
    @ObservableState
    struct State: Equatable {
        var salons: IdentifiedArrayOf<Salon>
    }
    enum Action {}
    var body: some Reducer<State, Action> { EmptyReducer() }
}

