import AVFoundation
import SwiftUI

/// 日本語の音声資産の案内（実装計画 §8、task_013）。
///
/// 2 つを別々に見せる。
/// - 聞き取り: `SpeechTranscriber` の ja-JP アセット。`TranscriptionService.prepare()` が
///   確認と取り込みの両方を行い、途中経過は `assetState` に出る。
/// - 読み上げ: `AVSpeechSynthesisVoice` の ja-JP。アプリからは取り込めないので、
///   enhanced / premium が無いときは設定アプリでの手順だけを示す（fix-decisions P5.8）。
@MainActor
struct AssetDownloadView: View {

    @State private var transcription = TranscriptionService()
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.assetTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.assetBody)
                .saydoText(.list)

            VStack(alignment: .leading, spacing: 10) {
                Text(transcriptionStatusText)
                    .saydoText(.list)
                if case .downloading(let fraction) = transcription.assetState {
                    ProgressView(value: fraction)
                        .tint(SaydoTheme.Palette.accent)
                }
                if didFail {
                    Button(OnboardingCopy.assetRetry) {
                        Task { await prepareTranscription(force: true) }
                    }
                    .buttonStyle(.plain)
                    .saydoText(.list)
                    .foregroundStyle(SaydoTheme.Palette.accent)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(voiceStatusText)
                    .saydoText(.list)
                if voiceQuality < .enhanced {
                    Text(OnboardingCopy.voiceDownloadSteps)
                        .saydoText(.status)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await prepareTranscription(force: false) }
    }

    // MARK: - 聞き取り

    private var transcriptionStatusText: String {
        if didFail { return OnboardingCopy.assetStateFailed }
        switch transcription.assetState {
        case .unknown: return OnboardingCopy.assetStateUnknown
        case .unsupported: return OnboardingCopy.assetStateUnsupported
        case .installed: return OnboardingCopy.assetStateInstalled
        case .downloading(let fraction): return OnboardingCopy.assetStateDownloading(fraction)
        }
    }

    /// `prepare()` はアセットの確認と取り込みを兼ねる（`TranscriptionService.prepare()`）。
    /// 取り込みだけを始める API は無いので、ここで呼ぶのが「取得を始める手段」になる。
    private func prepareTranscription(force: Bool) async {
        if !force, transcription.assetState == .installed { return }
        didFail = false
        do {
            _ = try await transcription.prepare()
        } catch TranscriptionFault.localeUnsupported {
            // `assetState` が `.unsupported` になっているので、その文言を出す。
        } catch {
            didFail = true
        }
    }

    // MARK: - 読み上げ

    private var voiceQuality: SynthesisVoiceQuality {
        guard let voice = SpeechSynthesisService.preferredJapaneseVoice() else { return .unavailable }
        return SynthesisVoiceQuality(voice.quality)
    }

    private var voiceStatusText: String {
        switch voiceQuality {
        case .unavailable: OnboardingCopy.voiceUnavailable
        case .standard: OnboardingCopy.voiceStandard
        case .enhanced, .premium: OnboardingCopy.voiceHighQuality
        }
    }
}
