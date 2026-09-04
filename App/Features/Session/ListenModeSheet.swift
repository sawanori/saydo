import SwiftUI

/// 再生前の配慮（retention R8 / 実装計画 §7.3）。
///
/// イヤホン未接続で音量が大きいまま鳴らすと、本人の声が周りに漏れる。TTS と宣言音声の
/// **前**にこれを出し、本人に返し方を選ばせる。「文字で読む」を選んでも体験は成立する
/// （宣言テキストを画面に出す）ので、どちらかを選ばせて終わりにする。
struct ListenModeSheet: View {

    private let onChoose: @MainActor (ListenMode) -> Void

    init(onChoose: @escaping @MainActor (ListenMode) -> Void) {
        self.onChoose = onChoose
    }

    var body: some View {
        HStack(spacing: 0) {
            choice(PlaybackCopy.listenWithEarphones, systemImage: "headphones") {
                onChoose(.speaker)
            }
            Rectangle()
                .fill(SaydoTheme.Palette.hairline)
                .frame(width: 1, height: 22)
            choice(PlaybackCopy.readAsText, systemImage: "text.alignleft") {
                onChoose(.readText)
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .saydoGround()
    }

    /// 塗り無し・高さ 46・ヘアラインの区切り（docs/design/Playback.dc.html）。
    private func choice(
        _ label: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.footnote)
                Text(label)
                    .saydoText(.status)
                    .tracking(0.56)
            }
            .foregroundStyle(SaydoTheme.Palette.ink3)
            .frame(maxWidth: .infinity)
            .frame(height: SaydoTheme.Metric.chipHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
