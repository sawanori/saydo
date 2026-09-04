import SwiftUI
import SaydoCore

/// 答えを選ばせるチップ（M1 の理由 7 種・N1 の状態 3 種・E0 の前進なし 2 種だけ）。
///
/// 意匠は `docs/design/SessionReason.dc.html`: 高さ 46・角丸 15・`Palette.chipFill`、
/// 7 個は **3 / 3 / 1 の意図的なラグ**（既定の文字サイズではそう並ぶ）。
///
/// 並べ方は `ChipFlowLayout` が実測幅で決める。`ViewThatFits` で行数の候補を並べる方法は、
/// 「何から始めるかわからない」のような長い 1 個が入らないだけで候補全体が落ちて
/// 1 行 1 個（7 行 = 382pt）まで転落するため採らない。文字サイズは xxxLarge を上限にする
/// （task_008 done_definition の「iPhone SE × xxxLarge で収まる」）。
struct ChoiceChipsView: View {

    let choices: [Choice]
    let onSelect: (Choice) -> Void

    var body: some View {
        ChipFlowLayout(
            rowSpacing: Layout.rowSpacing,
            chipSpacing: Layout.chipSpacing,
            rowHeight: SaydoTheme.Metric.chipHeight
        ) {
            ForEach(choices) { choice in
                ChoiceChip(choice: choice) { onSelect(choice) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private enum Layout {
        static let rowSpacing: CGFloat = 10
        static let chipSpacing: CGFloat = 10
    }
}

// MARK: - 並べ方

/// チップを左から詰め、入らなくなったら次の行へ送る。各行は中央に寄せる。
///
/// 高さは行数 × 46 + 行間。幅が足りない 1 個は行いっぱいまで縮めて置く
/// （その中で `minimumScaleFactor` が働く）。
struct ChipFlowLayout: Layout {

    var rowSpacing: CGFloat
    var chipSpacing: CGFloat
    var rowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let widths = idealWidths(of: subviews)
        let available = proposal.width ?? widths.reduce(0, +)
        let rows = rows(widths: widths, available: available)
        let height = CGFloat(rows.count) * rowHeight
            + CGFloat(max(0, rows.count - 1)) * rowSpacing
        let width = rows
            .map { rowWidth(of: $0, widths: widths, available: available) }
            .max() ?? 0
        return CGSize(width: min(available, max(width, 0)), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let widths = idealWidths(of: subviews)
        let available = bounds.width
        var y = bounds.minY
        for row in rows(widths: widths, available: available) {
            let total = rowWidth(of: row, widths: widths, available: available)
            var x = bounds.minX + max(0, (available - total) / 2)
            for index in row {
                let width = min(widths[index], available)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: rowHeight)
                )
                x += width + chipSpacing
            }
            y += rowHeight + rowSpacing
        }
    }

    // MARK: 内部

    private func idealWidths(of subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }

    /// 左から詰めて、入らなくなったら改行する。
    private func rows(widths: [CGFloat], available: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for index in widths.indices {
            let width = min(widths[index], available)
            let addition = current.isEmpty ? width : chipSpacing + width
            if !current.isEmpty, used + addition > available {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used += addition
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func rowWidth(of row: [Int], widths: [CGFloat], available: CGFloat) -> CGFloat {
        guard !row.isEmpty else { return 0 }
        let content = row.reduce(CGFloat.zero) { $0 + min(widths[$1], available) }
        return content + CGFloat(row.count - 1) * chipSpacing
    }
}

// MARK: - 1 個

private struct ChoiceChip: View {

    let choice: Choice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(choice.label)
                .saydoText(.list)
                .lineLimit(1)
                .minimumScaleFactor(Layout.minimumScale)
                .padding(.horizontal, Layout.horizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: SaydoTheme.Metric.chipHeight)
                .background(
                    RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                        .fill(SaydoTheme.Palette.chipFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                        .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
    }

    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let minimumScale: CGFloat = 0.7
    }
}
