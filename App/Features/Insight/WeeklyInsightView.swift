import SaydoCore
import SwiftUI

/// 「この 1 週間」（実装計画 §8、design-notes §画面別 6）。
///
/// 出すのは上位 5 分野・理由の割合・振り返り 1 文の 3 つだけ。
/// 円グラフ・達成率・平均縮小回数・連続日数は出さない（fix-decisions P2.2 / 企画原則 §22-8）。
struct WeeklyInsightView: View {

    /// design-notes §画面別 6 の実寸。
    private enum Layout {
        static let horizontalMargin: CGFloat = 30
        static let backButtonLeading: CGFloat = 8
        static let headerSpacing: CGFloat = 6
        static let sectionGap: CGFloat = 40
        static let labelGap: CGFloat = 22
        static let rankGap: CGFloat = 15
        static let rankNumberWidth: CGFloat = 20
        static let rankSpacing: CGFloat = 16
        static let barHeight: CGFloat = 12
        static let barGap: CGFloat = 2
        static let barEndRadius: CGFloat = 6
        static let barInnerRadius: CGFloat = 3
        static let legendGap: CGFloat = 11
        static let legendSpacing: CGFloat = 12
        static let legendSwatch: CGFloat = 10
        static let panelPadding: CGFloat = 22
        static let bottomPadding: CGFloat = 40
    }

    @Environment(\.dismiss) private var dismiss

    let model: InsightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionGap) {
                    header
                    content(for: model.state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Layout.horizontalMargin)
                .padding(.bottom, Layout.bottomPadding)
            }
        }
        .saydoGround()
    }

    // MARK: 見出し

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(SaydoTheme.TextRole.screenTitle.font)
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .frame(
                    width: SaydoTheme.Metric.keyboardButtonSize,
                    height: SaydoTheme.Metric.keyboardButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(InsightViewCopy.closeAccessibilityLabel)
        .padding(.leading, Layout.backButtonLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            Text(InsightViewCopy.weeklyTitle)
                .saydoText(.screenTitle)
            if case .weekly(let insight) = model.state {
                Text(dateRange(of: insight))
                    .saydoText(.time)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 状態ごとの中身

    @ViewBuilder
    private func content(for state: InsightViewModel.State) -> some View {
        switch state {
        case .insufficient:
            reflectionPanel(InsightCopy.notEnoughData)
        case .firstInsight(let line):
            VStack(alignment: .leading, spacing: Layout.sectionGap) {
                Text(InsightViewCopy.emphasized(line, emphasis: SaydoTheme.Palette.accent))
                    .saydoText(.declaration)
                    .frame(maxWidth: .infinity, alignment: .leading)
                reflectionPanel(InsightCopy.notEnoughData)
            }
        case .weekly(let insight):
            VStack(alignment: .leading, spacing: Layout.sectionGap) {
                topDomains(insight.topDomains)
                if !insight.reasons.isEmpty {
                    reasons(insight.reasons)
                }
                reflectionPanel(insight.reflection)
            }
        }
    }

    /// あなたが逃げやすいこと。件数は出さない（design-notes §画面別 6）。
    private func topDomains(_ domains: [TaskDomain]) -> some View {
        VStack(alignment: .leading, spacing: Layout.labelGap) {
            Text(InsightViewCopy.topDomainsLabel)
                .saydoText(.sectionLabel)
            VStack(alignment: .leading, spacing: Layout.rankGap) {
                ForEach(Array(domains.enumerated()), id: \.element) { index, domain in
                    HStack(alignment: .firstTextBaseline, spacing: Layout.rankSpacing) {
                        Text(rank(index))
                            .saydoText(.time)
                            .frame(width: Layout.rankNumberWidth, alignment: .leading)
                        Text(domain.displayName)
                            .saydoText(index == 0 ? .declaration : .list)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 逃げる理由。帯の実幅を割合に比例させ、凡例に割合を添える。
    private func reasons(_ shares: [ReasonShare]) -> some View {
        VStack(alignment: .leading, spacing: Layout.labelGap) {
            Text(InsightViewCopy.reasonsLabel)
                .saydoText(.sectionLabel)

            GeometryReader { proxy in
                let gaps = CGFloat(max(0, shares.count - 1)) * Layout.barGap
                let available = max(0, proxy.size.width - gaps)
                HStack(spacing: Layout.barGap) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        segment(at: index, of: shares.count)
                            .fill(rampColor(at: index))
                            .frame(width: available * share.ratio)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: Layout.barHeight)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Layout.legendGap) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: Layout.legendSpacing) {
                        RoundedRectangle(cornerRadius: Layout.barInnerRadius)
                            .fill(rampColor(at: index))
                            .frame(width: Layout.legendSwatch, height: Layout.legendSwatch)
                        Text(share.reason.displayName)
                            .saydoText(.list)
                        Spacer(minLength: Layout.legendSpacing)
                        Text(share.ratio.formatted(.percent.precision(.fractionLength(0))))
                            .saydoText(.time)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 振り返り 1 文。温色のパネルに置く。
    private func reflectionPanel(_ text: String) -> some View {
        Text(text)
            .saydoText(.reflection)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.panelPadding)
            .background(
                SaydoTheme.Palette.glow,
                in: RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius)
            )
    }

    // MARK: 部品

    private func rank(_ index: Int) -> String {
        String(format: "%02d", index + 1)
    }

    private func rampColor(at index: Int) -> Color {
        let ramp = SaydoTheme.Palette.accentRamp
        return ramp[min(index, ramp.count - 1)]
    }

    private func segment(at index: Int, of count: Int) -> UnevenRoundedRectangle {
        let leading = index == 0 ? Layout.barEndRadius : Layout.barInnerRadius
        let trailing = index == count - 1 ? Layout.barEndRadius : Layout.barInnerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing
        )
    }

    private func dateRange(of insight: WeeklyInsight) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return insight.firstDay.formatted(style)
            + InsightViewCopy.periodSeparator
            + insight.lastDay.formatted(style)
    }
}
