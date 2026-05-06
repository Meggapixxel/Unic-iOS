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
