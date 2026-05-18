//
//  WorksOnTagEditor.swift
//  unic-ios
//

import SwiftUI

/// Thin wrapper around `TagEditor` pre-wired to the `worksOnTags` collection in `FirebaseService`.
/// Kept for backwards-compatible call sites that don't need to inject the tag catalogue directly.
struct WorksOnTagEditor: View {
    @Binding var selectedTags: [String]
    @ObservedObject private var service = FirebaseService.shared

    var body: some View {
        TagEditor(
            selectedIds: $selectedTags,
            availableTags: service.worksOnTags,
            placeholder: "works_on_search",
            onAddNew: { name in try await service.addWorksOnTag(name) }
        )
    }
}

// MARK: - Tag Chip

/// Capsule chip displaying a tag name with an `xmark` remove button.
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
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

/// Custom `Layout` that wraps child views into multiple rows like CSS `flex-wrap`.
struct FlowLayout: Layout {
    /// Horizontal and vertical gap between adjacent views.
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
