//
//  TagEditor.swift
//  unic-ios
//

import SwiftUI

/// Reusable inline tag editor with chip display, search-as-you-type suggestions, and optional new-tag creation.
struct TagEditor: View {
    /// IDs of the currently selected tags; updated in place as the user adds/removes chips.
    @Binding var selectedIds: [String]
    /// Full catalogue of available tags to suggest from.
    let availableTags: [TagItem]
    let placeholder: LocalizedStringKey
    /// When `false` the "+" add-new button is hidden even if `onAddNew` is provided.
    var canAddNew: Bool = true
    /// Called with the new tag name; must return the Firestore document ID of the created tag.
    /// Pass `nil` to disable tag creation.
    let onAddNew: ((String) async throws -> String)?

    @State private var inputText = ""
    @State private var addError: String?

    private var suggestions: [TagItem] {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return availableTags.filter {
            $0.name.lowercased().contains(query) && !selectedIds.contains($0.id)
        }
    }

    private var showAddButton: Bool {
        guard canAddNew, onAddNew != nil else { return false }
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIds.removeAll { $0 == tagId }
                            }
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
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
                    .buttonStyle(.borderless)
                }
            }

            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { tag in
                        Text(tag.name)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(12)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    addExisting(tag)
                                }
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIds)
        .animation(.easeInOut(duration: 0.2), value: suggestions.map(\.id))
        .alert(String.error, isPresented: Binding(
            get: { addError != nil },
            set: { if !$0 { addError = nil } }
        )) {
            Button(String.ok, role: .cancel) {}
        } message: {
            Text(addError ?? "")
        }
    }

    private func addExisting(_ tag: TagItem) {
        guard !selectedIds.contains(tag.id) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedIds.append(tag.id)
            inputText = ""
        }
    }

    private func addNewTag(_ name: String) {
        guard !name.isEmpty, let onAddNew else { return }
        inputText = ""
        Task {
            do {
                let id = try await onAddNew(name)
                await MainActor.run {
                    if !selectedIds.contains(id) {
                        selectedIds.append(id)
                    }
                }
            } catch {
                await MainActor.run { addError = error.localizedDescription }
            }
        }
    }
}
