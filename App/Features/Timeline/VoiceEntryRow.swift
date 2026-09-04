import SwiftUI

/// タイムラインの 1 行（`docs/design/Timeline.dc.html` の 5.）。
///
/// マイクのストロークアイコン + 時刻 + 文字起こし 1〜2 行 + 32pt の再生ボタン。
/// `audioPath` が nil の行（チップだけで答えた場面）は再生ボタンを出さず文字起こしだけを見せる。
struct VoiceEntryRow: View {
    /// design-notes 5. の寸法。`SaydoTheme.Metric` に該当する値が無いのでここに置く。
    /// グリフだけ固定サイズなのは、縦レールを断つ台座の幅と再生の丸が
    /// Dynamic Type で崩れないようにするため。文字は Dynamic Type で伸びる。
    enum Metric {
        static let glyphColumnWidth: CGFloat = 18
        static let glyphColumnHeight: CGFloat = 32
        static let glyphColumnCornerRadius: CGFloat = 9
        static let columnSpacing: CGFloat = 13
        static let playButtonDiameter: CGFloat = 32
        static let playButtonHitArea: CGFloat = 44
        static let micGlyphSize: CGFloat = 15
        static let playGlyphSize: CGFloat = 11
    }

    let entry: VoiceEntrySnapshot
    /// この行が鳴っているか。
    let isPlaying: Bool
    /// 再生ボタンのタップ。音声を持たない行では呼ばれない。
    let onPlayTapped: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Metric.columnSpacing) {
            micGlyph
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: Metric.columnSpacing) {
                    Text(
                        entry.recordedAt,
                        format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                    )
                    .saydoText(.time)
                    .foregroundStyle(isPlaying ? SaydoTheme.Palette.accent : SaydoTheme.TextRole.time.color)

                    Spacer(minLength: 0)

                    if entry.audioPath != nil {
                        playButton
                    }
                }
                .frame(minHeight: Metric.glyphColumnHeight)

                Text(entry.transcript)
                    .saydoText(.list)
                    .foregroundStyle(isPlaying ? SaydoTheme.Palette.accent : SaydoTheme.TextRole.list.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// マイク。背後の面で縦レールを断つ（design-notes 5.）。
    private var micGlyph: some View {
        Image(systemName: "mic")
            .font(.system(size: Metric.micGlyphSize, weight: .light))
            .foregroundStyle(SaydoTheme.Palette.accent.opacity(isPlaying ? 1 : 0.8))
            .frame(width: Metric.glyphColumnWidth, height: Metric.glyphColumnHeight)
            .background(
                SaydoTheme.Palette.groundMid,
                in: RoundedRectangle(cornerRadius: Metric.glyphColumnCornerRadius)
            )
            .accessibilityHidden(true)
    }

    private var playButton: some View {
        Button(action: onPlayTapped) {
            ZStack {
                Circle()
                    .strokeBorder(SaydoTheme.Palette.hairline, lineWidth: 1)
                    .frame(width: Metric.playButtonDiameter, height: Metric.playButtonDiameter)
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: Metric.playGlyphSize))
                    .foregroundStyle(isPlaying ? SaydoTheme.Palette.accent : SaydoTheme.Palette.ink3)
            }
            .frame(width: Metric.playButtonHitArea, height: Metric.playButtonHitArea)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? TimelineCopy.stop : TimelineCopy.play)
    }
}
