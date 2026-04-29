//
//  TagEditor.swift
//  unic-ios
//

import SwiftUI

struct TagEditor: View {
    @Binding var selectedIds: [String]
    let availableTags: [TagItem]
    let placeholder: LocalizedStringKey
    var canAddNew: Bool = true
    let onAddNew: ((String) async throws -> String)?

    @State private var inputText = ""

    private var suggestions: [TagItem] {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return availableTags.filter {
            $0.name.lowercased().contains(query) && !selectedIds.contains($0.id)
        }
    }

    private var showAddButton: Bool {
        guard canAddNew, let _ = onAddNew else { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !availableTags.contains(where: { $0.name.lowercased() == trimmed.lowercased() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selectedIds.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedIds, id: \.self) { tagId in
                        let name = availableTags.first(where: { $0.id == tagId })?.name ?? tagId
                        TagChip(title: name) {
                            selectedIds.removeAll { $0 == tagId }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                TextField(placeholder, text: $inputText)
                    .autocorrectionDisabled()

                if showAddButton {
                    Button {
                        addNewTag(inputText.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .imageScale(.large)
                    }
                }
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { tag in
                            Button {
                                addExisting(tag)
                            } label: {
                                Text(tag.name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addExisting(_ tag: TagItem) {
        guard !selectedIds.contains(tag.id) else { return }
        selectedIds.append(tag.id)
        inputText = ""
    }

    private func addNewTag(_ name: String) {
        guard !name.isEmpty, let onAddNew else { return }
        inputText = ""
        Task {
            guard let id = try? await onAddNew(name) else { return }
            await MainActor.run {
                if !selectedIds.contains(id) {
                    selectedIds.append(id)
                }
            }
        }
    }
}
