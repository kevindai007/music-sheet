import MusicSheetKit
import SwiftUI

/// One lyric line with its chords drawn above the characters where they change.
struct LyricLineView: View {
    let line: SongSheet.Line
    let formatChord: (String) -> String
    var isActive = false

    var body: some View {
        FlowLayout {
            ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                VStack(alignment: .leading, spacing: 0) {
                    Text(segment.chord.map(formatChord) ?? " ")
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 6)
                    Text(segment.text.isEmpty ? " " : segment.text)
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

/// Lays children out left to right, wrapping to a new row when the width runs out.
struct FlowLayout: Layout {
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
