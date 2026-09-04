import SaydoCore
import SwiftUI
import UIKit

/// 通知以外から開いたときの入口（実装計画 §8 / docs/design/Today.dc.html）。
///
/// 置くのは「今日の約束」1 件と「今話す」だけ。一覧・チェックボックス・進捗率・連続日数は
/// 作らない（企画原則 §22-8）。宣言音声はここからも本人に返せる（§22-10）。
struct TodayView: View {

    private let repository: Repository
    private let player: any Playing
    private let notificationHealth: NotificationHealth?
    private let onStartSession: @MainActor (SessionType) -> Void
    private let onOpenSettings: @MainActor () -> Void
    /// 宣言音声の相対パスを URL に直す。開けない環境では再生ボタンを出さない。
    private let audioFiles: AudioFileStore?

    @Environment(\.openURL) private var openURL

    @State private var commitment: CommitmentSnapshot?
    /// 夜まで終えた日か（E1 の `VoiceEntry` が残っているか）。
    @State private var isDayFinished = false
    @State private var hasLoaded = false

    init(
        repository: Repository,
        player: any Playing,
        notificationHealth: NotificationHealth?,
        onStartSession: @escaping @MainActor (SessionType) -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.repository = repository
        self.player = player
        self.notificationHealth = notificationHealth
        self.onStartSession = onStartSession
        self.onOpenSettings = onOpenSettings
        self.audioFiles = try? AudioFileStore.applicationSupport()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 44)
            promise
            Spacer(minLength: 24)
            if let notificationHealth, notificationHealth.needsAttention {
                notificationNotice
            }
            Spacer(minLength: 24)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .saydoGround()
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    // MARK: 上部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "SAYDO")
                .saydoText(.logo)
            Spacer()
            Text(Date.now.formatted(Self.dayStyle))
                .saydoText(.time)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.footnote)
                    .foregroundStyle(SaydoTheme.Palette.ink4)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodayCopy.settings)
        }
    }

    private static let dayStyle = Date.FormatStyle
        .dateTime
        .locale(Locale(identifier: "ja_JP"))
        .month(.defaultDigits)
        .day()
        .weekday(.abbreviated)

    private static let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        .locale(Locale(identifier: "ja_JP"))

    // MARK: 今日の約束

    @ViewBuilder
    private var promise: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(TodayCopy.promiseSectionLabel)
                .saydoText(.sectionLabel)
            if let commitment {
                declarationCard(commitment)
            } else {
                Text(TodayCopy.noPromiseYet)
                    .saydoText(.declaration)
                    .foregroundStyle(SaydoTheme.Palette.ink3)
            }
        }
    }

    private func declarationCard(_ commitment: CommitmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(commitment.microAction.text)
                .saydoText(.declaration)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(SaydoTheme.Palette.hairline)
                .frame(height: 1)
                .padding(.top, 22)
                .padding(.bottom, 18)

            HStack(alignment: .center) {
                if let plannedAt = commitment.plannedAt {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(TodayCopy.actionTimeLabel)
                            .saydoText(.sectionLabel)
                        Text(
                            TodayCopy.plannedLabel(
                                time: plannedAt.formatted(Self.timeStyle),
                                place: commitment.plannedPlace
                            )
                        )
                        .font(.title3.weight(.medium).monospacedDigit())
                        .foregroundStyle(SaydoTheme.Palette.accent)
                    }
                }
                Spacer(minLength: 12)
                if commitment.declarationAudioPath != nil {
                    playButton
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                .fill(SaydoTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
        )
    }

    /// 48px の再生ボタン。朝の自分の声をその場で返す。
    private var playButton: some View {
        Button {
            Task { await playDeclaration() }
        } label: {
            Image(systemName: "play.fill")
                .font(.footnote)
                .foregroundStyle(SaydoTheme.Palette.accent)
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(SaydoTheme.Palette.accent.opacity(0.09))
                )
                .overlay(
                    Circle().stroke(SaydoTheme.Palette.accent.opacity(0.42), lineWidth: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TodayCopy.playDeclaration)
    }

    // MARK: 通知の再許可

    /// 通知が唯一の入口なので、黙って壊れたままにしない（実装計画 §7.4）。
    private var notificationNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TodayCopy.notificationsStopped)
                .saydoText(.list)
            Button(TodayCopy.openSystemSettings) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(SaydoTheme.Palette.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                .fill(SaydoTheme.Palette.chipFill)
        )
    }

    // MARK: 下部

    @ViewBuilder
    private var footer: some View {
        if isDayFinished {
            Text(TodayCopy.dayFinished)
                .saydoText(.status)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                onStartSession(commitment == nil ? .morning : .adhoc)
            } label: {
                Text(TodayCopy.speakNow)
                    .font(.body.weight(.medium))
                    .tracking(1.7)
                    .foregroundStyle(SaydoTheme.Palette.accentHighlight)
                    .frame(maxWidth: .infinity)
                    .frame(height: SaydoTheme.Metric.primaryButtonHeight)
                    .background(
                        Capsule().fill(SaydoTheme.Palette.accent.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(SaydoTheme.Palette.accent.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 読み込み

    private func load() async {
        let today = Date.now
        commitment = try? await repository.todayCommitment(on: today)
        let entries = (try? await repository.entries(for: today)) ?? []
        // 夜 E1 まで終えた日は「今日はここまで」。件数も達成率も出さない。
        isDayFinished = entries.contains { $0.kind == .tomorrow }
    }

    private func playDeclaration() async {
        guard let path = commitment?.declarationAudioPath, let audioFiles else { return }
        try? await player.play(audioFiles.url(forRelativePath: path), preferReceiver: false)
    }
}
