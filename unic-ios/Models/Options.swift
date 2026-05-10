//
//  Options.swift
//  unic-ios
//
//  Created by UNIC Team on 04/02/2026.
//

import Foundation
import IdentifiedCollections

struct BusinessType: Identifiable, Hashable {
    let id: String
    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
    }
}

struct LanguageOption: Identifiable, Hashable {
    let id: String
    var displayName: String {
        Locale.current.localizedString(forLanguageCode: id) ?? id.uppercased()
    }
}

enum DateRangeOption: String, CaseIterable, Identifiable {
    case thisWeek    = "thisWeek"
    case thisMonth   = "thisMonth"
    case last3Months = "last3Months"
    case thisYear    = "thisYear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisWeek:    return String.filter_date_this_week
        case .thisMonth:   return String.filter_date_this_month
        case .last3Months: return String.filter_date_last_3_months
        case .thisYear:    return String.filter_date_this_year
        }
    }

    func includes(_ date: Date) -> Bool {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .thisWeek:
            return cal.date(byAdding: .day, value: -7, to: now)! <= date
        case .thisMonth:
            return date >= cal.date(from: cal.dateComponents([.year, .month], from: now))!
        case .last3Months:
            return cal.date(byAdding: .month, value: -3, to: now)! <= date
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
            return date >= start
        }
    }
}

struct Options<T: Identifiable & Hashable> {
    private(set) var all: IdentifiedArrayOf<T> = []
    private(set) var selected: Set<T.ID> = []

    init(all: IdentifiedArrayOf<T> = [], selected: Set<T.ID> = []) {
        self.all = all
        self.selected = selected
    }

    var selectedItems: [T] {
        all.filter { selected.contains($0.id) }
    }

    var hasSelection: Bool {
        !selected.isEmpty
    }

    mutating func toggle(_ item: T) {
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
    }

    mutating func clear() {
        selected.removeAll()
    }

    mutating func setAll(_ items: IdentifiedArrayOf<T>) {
        all = items
    }

    func isSelected(_ item: T) -> Bool {
        selected.contains(item.id)
    }
}
