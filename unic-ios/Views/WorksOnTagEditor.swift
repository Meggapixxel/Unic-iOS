//
//  WorksOnTagEditor.swift
//  unic-ios
//

import SwiftUI

// MARK: - Tag Editor

struct WorksOnTagEditor: View {
    @Binding var selectedTags: [String]  // stores tag IDs
    @ObservedObject private var service = FirebaseService.shared

    @State private var inputText = ""

    private var suggestions: [WorksOnTag] {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return service.worksOnTags.filter {
            $0.name.lowercased().contains(query) && !selectedTags.contains($0.id)
        }
    }

    private var isNewTag: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !service.worksOnTags.contains(where: { $0.name.lowercased() == trimmed.lowercased() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selectedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tagId in
                        let name = service.worksOnTags.first(where: { $0.id == tagId })?.name ?? tagId
                        TagChip(title: name) {
                            selectedTags.removeAll { $0 == tagId }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                TextField(String(localized: "works_on_search"), text: $inputText)
                    .autocorrectionDisabled()

                if isNewTag {
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
                                addExistingTag(tag)
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

    private func addExistingTag(_ tag: WorksOnTag) {
        guard !selectedTags.contains(tag.id) else { return }
        selectedTags.append(tag.id)
        inputText = ""
    }

    private func addNewTag(_ name: String) {
        guard !name.isEmpty else { return }
        inputText = ""
        Task {
            guard let id = try? await service.addWorksOnTag(name) else { return }
            await MainActor.run {
                if !selectedTags.contains(id) {
                    selectedTags.append(id)
                }
            }
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: frame.minX + bounds.minX, y: frame.minY + bounds.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let viewSize = subview.sizeThatFits(.unspecified)
                if x + viewSize.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: viewSize))
                x += viewSize.width + spacing
                rowHeight = max(rowHeight, viewSize.height)
            }
            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
