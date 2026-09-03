import SwiftUI

/// Lays subviews left to right, wrapping onto a new line when the next one will not
/// fit — what a row of tags needs and what no stack gives you.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                             cache: inout ()) -> CGSize {
        // With no width proposed, answer with the *narrowest* width this can work in —
        // one chip wide — not the widest it would enjoy.
        //
        // A Form sizes its label column from what each row asks for. Answering "one
        // long line, please" made the tag row demand more width than any other, so its
        // label was shoved left while Folder, Notes and Size stayed put, and the column
        // visibly moved as tags were added. Asking for the minimum lets the Form give
        // this row the same space as the rest.
        let limit = proposal.width ?? (subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
        let rows = arrange(subviews, within: limit)
        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height + (total > 0 ? lineSpacing : 0)
        }
        return CGSize(width: limit, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                              subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, within: bounds.width) {
            var x = bounds.minX
            for entry in row.entries {
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y + (row.height - entry.size.height) / 2),
                    proposal: ProposedViewSize(entry.size)
                )
                x += entry.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var entries: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, within limit: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.entries.isEmpty ? size.width : row.width + spacing + size.width
            if !row.entries.isEmpty && needed > limit {
                rows.append(row)
                row = Row()
            }
            row.width = row.entries.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.entries.append((index, size))
        }
        if !row.entries.isEmpty { rows.append(row) }
        return rows
    }
}
