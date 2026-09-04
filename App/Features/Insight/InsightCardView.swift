import SaydoCore
import SwiftUI

/// Timeline 上部の 1 行インサイト（design-notes §画面別 5、retention R9）。
///
/// `TimelineView` の `topAccessory` に差し込んで使う。記録が足りない間は `EmptyView` を返し、
/// 空白のプレースホルダを置かない（retention R4 / 企画原則 §22-8）。
struct InsightCardView: View {

    /// design-notes §画面別 5 の実寸。
    private enum Layout {
        /// 温色のルール。
        static let ruleWidth: CGFloat = 26
        static let ruleHeight: CGFloat = 1
        static let ruleOpacity: Double = 0.55
        /// ルールと文の間。
        static let stackSpacing: CGFloat = 13
        /// 文とシェブロンの間。
        static let rowSpacing: CGFloat = 14
    }

    let model: InsightViewModel

    @State private var isShowingWeekly = false

    var body: some View {
        if let line = model.cardLine {
            Button {
                isShowingWeekly = true
            } label: {
                row(line)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(InsightViewCopy.openWeeklyAccessibilityLabel)
            .accessibilityValue(line)
            .sheet(isPresented: $isShowingWeekly) {
                WeeklyInsightView(model: model)
            }
        }
    }

    private func row(_ line: String) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            VStack(alignment: .leading, spacing: Layout.stackSpacing) {
                Rectangle()
                    .fill(SaydoTheme.Palette.accent)
                    .frame(width: Layout.ruleWidth, height: Layout.ruleHeight)
                    .opacity(Layout.ruleOpacity)

                Text(InsightViewCopy.emphasized(line, emphasis: SaydoTheme.Palette.accent))
                    .saydoText(.list)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Image(systemName: "chevron.right")
                .font(SaydoTheme.TextRole.time.font)
                .foregroundStyle(SaydoTheme.Palette.ink4)
        }
        .contentShape(Rectangle())
    }
}
