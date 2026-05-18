//
//  Options.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import IdentifiedCollections

/// A business-type category used to classify salons (e.g. `"HAIR_SALON"`).
struct BusinessType: Identifiable, Hashable {
    let id: String
    /// Human-readable label derived from the raw ID by replacing underscores with spaces.
    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
    }
}

/// A language option identified by its BCP-47 language code (e.g. `"en"`, `"uk"`).
struct LanguageOption: Identifiable, Hashable {
    /// BCP-47 language code.
    let id: String
    /// Localised name of the language as reported by the current `Locale`.
    var displayName: String {
        Locale.current.localizedString(forLanguageCode: id) ?? id.uppercased()
    }
}

/// Predefined date-range filter options available in list views.
enum DateRangeOption: String, CaseIterable, Identifiable {
    case thisMonth = "thisMonth"
    case thisYear  = "thisYear"

    var id: String { rawValue }

    /// Localised label for display in a picker or filter chip.
    var displayName: String {
        switch self {
        case .thisMonth: return String.filter_date_this_month
        case .thisYear:  return String.filter_date_this_year
        }
    }

    /// Returns `true` when `date` falls within the range represented by this option.
    /// - Parameter date: The date to test against the current calendar.
    func includes(_ date: Date) -> Bool {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .thisMonth:
            return date >= cal.date(from: cal.dateComponents([.year, .month], from: now))!
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
            return date >= start
        }
    }
}

/// Generic multi-select container that pairs a full item list with a set of selected IDs.
///
/// Use this as the backing state for filter pickers, tag selectors, and similar UI controls.
struct Options<T: Identifiable & Hashable> {
    /// All available items in display order.
    private(set) var all: IdentifiedArrayOf<T> = []
    /// IDs of the currently selected items.
    private(set) var selected: Set<T.ID> = []

    /// Creates an `Options` container with an optional pre-populated list and selection.
    /// - Parameters:
    ///   - all: The full set of available items.
    ///   - selected: IDs to mark as selected initially.
    init(all: IdentifiedArrayOf<T> = [], selected: Set<T.ID> = []) {
        self.all = all
        self.selected = selected
    }

    /// The subset of `all` whose IDs appear in `selected`, preserving `all` order.
    var selectedItems: [T] {
        all.filter { selected.contains($0.id) }
    }

    /// `true` when at least one item is selected.
    var hasSelection: Bool {
        !selected.isEmpty
    }

    /// Toggles the selection state of `item`.
    /// - Parameter item: The item to select or deselect.
    mutating func toggle(_ item: T) {
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
    }

    /// Deselects all items.
    mutating func clear() {
        selected.removeAll()
    }

    /// Replaces the full item list, preserving the current selection.
    /// - Parameter items: New item list to adopt.
    mutating func setAll(_ items: IdentifiedArrayOf<T>) {
        all = items
    }

    /// Returns `true` when `item` is currently selected.
    /// - Parameter item: The item to check.
    func isSelected(_ item: T) -> Bool {
        selected.contains(item.id)
    }
}
