import Foundation

/// オンボーディングの文言（実装計画 §8、task_013）。
///
/// 画面ファイルに日本語を直書きしない（CLAUDE.md §1）。
/// 責める語彙を置かない（企画原則 §22-1）。権限を断った人にも同じ調子で話す。
enum OnboardingCopy {

    // MARK: - 共通

    static let next = "次へ"
    static let back = "戻る"
    static let skip = "あとで決める"
    static let finish = "はじめる"
    static let openSystemSettings = "設定を開く"

    // MARK: - コンセプト

    static let conceptTitle = "SAYDO"
    static let conceptBody = "逃げていることを、自分の声で認めて、一歩だけ動く。"
    static let conceptDetail = "朝に 30 秒だけ話します。それだけです。"

    // MARK: - マイク

    static let microphoneTitle = "あなたの声を録ります"
    static let microphoneBody = "録った声はこの端末の中だけに置き、あとであなた自身に返します。"
    static let microphoneRequest = "マイクを許可する"
    static let microphoneGranted = "マイクを使えます。"
    static let microphoneDenied = "マイクは使わないままでも、文字だけで最後まで進められます。"
    static let microphoneDeniedHint = "あとで声を使いたくなったら、設定アプリから変えられます。"

    // MARK: - 通知

    static let notificationTitle = "通知が入口です"
    static let notificationBody = "朝に 1 通と、あなたが決めた行動の時刻に 1 通。それだけ届きます。"
    static let notificationRequest = "通知を許可する"
    static let notificationGranted = "通知を送れます。"
    static let notificationDenied = "通知なしでも、アプリを開けばいつでも話せます。"
    static let notificationDeniedHint = "あとで通知を受け取りたくなったら、設定アプリから変えられます。"

    // MARK: - 回数と時刻

    static let scheduleTitle = "いつ声をかけますか"
    static let scheduleBody = "既定は朝の 1 通と、行動の時刻の 1 通です。"
    static let modeLabel = "固定の通知"
    static let modeTwoPerDay = "朝だけ"
    static let modeThreePerDay = "朝・昼・夜"
    static let morningTimeLabel = "朝"
    static let noonTimeLabel = "昼"
    static let nightTimeLabel = "夜"

    // MARK: - 一人で話せる時間

    static let aloneTitle = "一人で話せる時間"
    static let aloneBody = "宣言を後回しにした日に、この時刻に 1 回だけ声をかけます。"
    static let aloneTimeLabel = "時刻"
    static let aloneUnanswered = "決めないままなら、夜の時刻を使います。"
    static let aloneSetToggle = "時刻を決める"

    // MARK: - 日本語の音声

    static let assetTitle = "日本語の音声を用意します"
    static let assetBody = "聞き取りと読み上げは、この端末の中だけで動きます。"

    /// 聞き取りモデル（`SpeechTranscriber` の ja-JP アセット）の状態。
    static let assetStateUnknown = "確認しています…"
    static let assetStateInstalled = "聞き取りの準備ができています。"
    static let assetStateUnsupported = "この端末では日本語の聞き取りを使えません。文字だけで進められます。"
    static let assetStateFailed = "いまは準備できませんでした。あとでもう一度試せます。"
    static let assetRetry = "もう一度試す"

    static func assetStateDownloading(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        return "日本語の音声を取り込んでいます（\(percent)%）"
    }

    /// 読み上げ音声（`AVSpeechSynthesisVoice`）の品質。
    static let voiceHighQuality = "読み上げに高品質の日本語音声を使えます。"
    static let voiceStandard = "いまは端末の既定の音声で読み上げます。"
    static let voiceUnavailable = "この端末には日本語の読み上げ音声がありません。文字で読む形でも進められます。"
    static let voiceDownloadSteps = "高品質の音声は、設定アプリの「アクセシビリティ」→「読み上げコンテンツ」→「声」→「日本語」から追加できます。"

    // MARK: - バックアップ

    static let backupTitle = "録音の置き場所"
    static let backupBody = "音声はこの端末の中だけに残ります。外へは送りません。"
    static let backupWarning = "iCloud バックアップが無効だと、機種変更や初期化のときに音声を引き継げません。設定アプリの「iCloud」→「iCloud バックアップ」から確認できます。"
    static let backupSizeNote = "音声は 1 件あたり約 60 KB、1 年でおよそ 110 MB です。"
}
