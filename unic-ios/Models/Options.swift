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

struct Category: Identifiable, Hashable {
    let id: String
    var displayName: String { id }
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
