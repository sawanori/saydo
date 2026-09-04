import Foundation

/// 設定画面の文言（実装計画 §8、task_013 / task_019）。
///
/// 画面ファイルに日本語を直書きしない（CLAUDE.md §1）。
/// 「未達成」「失敗」を項目名に使わない（企画原則 §22-1・§22-7）。
enum SettingsCopy {

    static let title = "設定"
    static let close = "閉じる"

    // MARK: - 通知

    static let notificationSection = "通知"
    static let modeLabel = "固定の通知"
    static let modeTwoPerDay = "朝だけ"
    static let modeThreePerDay = "朝・昼・夜"
    static let modeFootnote = "行動の時刻の通知は、朝に決めた日だけ届きます。"
    static let morningTimeLabel = "朝"
    static let noonTimeLabel = "昼"
    static let nightTimeLabel = "夜"
    static let weekendLabel = "週末も通知する"
    static let weekendFootnote = "切ると土曜と日曜は固定の通知を送りません。"

    // MARK: - 一人で話せる時間

    static let aloneSection = "一人で話せる時間"
    static let aloneToggle = "時刻を決める"
    static let aloneTimeLabel = "時刻"
    static let aloneFootnote = "宣言を後回しにした日に、この時刻に 1 回だけ声をかけます。決めないままなら夜の時刻を使います。"

    // MARK: - 声

    static let voiceSection = "声"
    static let ttsVoiceLabel = "読み上げの声"
    static let ttsVoiceSystemDefault = "端末の既定"
    static let ttsVoiceDownloadHint = "高品質の音声は、設定アプリの「アクセシビリティ」→「読み上げコンテンツ」→「声」→「日本語」から追加できます。"
    static let silenceLabel = "話し終わりの間"
    static let silenceFootnote = "この長さだけ黙ると、話し終わりとして受け取ります。"

    static func silenceChoice(_ seconds: Double) -> String {
        String(format: "%.1f 秒", seconds)
    }

    /// 読み上げ音声 1 件の見出し（`AVSpeechSynthesisVoice` の名前 + 品質）。
    static func voiceName(_ name: String, isHighQuality: Bool) -> String {
        isHighQuality ? "\(name)（高品質）" : name
    }

    // MARK: - 話せない時

    static let quietSection = "話せない時"
    static let quietToggle = "決めた時間帯は文字で進める"
    static let quietStartLabel = "開始"
    static let quietEndLabel = "終了"
    static let quietFootnote = "この時間帯に開いた会話は、最初から選択肢と短い入力で進みます。読み上げは文字で出ます。"

    // MARK: - データ

    static let dataSection = "データ"
    static let backupNotice = "音声はこの端末の中だけに残ります。iCloud バックアップが無効だと、機種変更や初期化のときに引き継げません。"
    static let exportButton = "データを書き出す"
    static let exportInProgress = "書き出しています…"
    static let exportShare = "書き出したファイルを送る"
    static let exportFailed = "いまは書き出せませんでした。あとでもう一度試せます。"

    static func exportReady(fileCount: Int) -> String {
        "音声 \(fileCount) 件を含むファイルができました。"
    }

    static let deleteButton = "データを全部消す"
    static let deleteConfirmTitle = "この端末の記録を全部消しますか？"
    static let deleteConfirmMessage = "音声も、宣言も、記録も戻せません。書き出しておくと手元に残せます。"
    static let deleteConfirmAction = "消す"
    static let deleteCancel = "やめる"
    static let deleteInProgress = "消しています…"
    static let deleteFailed = "いまは消せませんでした。あとでもう一度試せます。"

    /// 完了の 1 文。責めず、次に何が起きるかだけを言う（企画原則 §22-1）。
    static func deleteDone(recordCount: Int, audioFileCount: Int) -> String {
        "記録 \(recordCount) 件と音声 \(audioFileCount) 件を消しました。ここから、また一つだけ。"
    }

    // MARK: - 開発者向け

    static let developerSection = "開発者向け"
    static let developerFootnote = "端末の中だけで数えた値です。外へは送りません。"
    static let developerEmpty = "まだ記録がありません。"
    static let sessionCompletionLabel = "会話が最後まで進んだ割合"
    static let sessionDurationLabel = "会話にかかった時間の中央値"
    static let outcomeLabel = "宣言のあとの答え"
    static let shrinkLabel = "「もっと小さく」の平均回数"
    static let voicelessLabel = "声を使わずに宣言した回数"
    static let noCommitmentDaysLabel = "宣言をしなかった日"

    static func developerWindow(days: Int) -> String {
        "直近 \(days) 日"
    }

    static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }

    static func count(_ value: Int) -> String {
        "\(value) 件"
    }

    static func days(_ value: Int) -> String {
        "\(value) 日"
    }

    static func average(_ value: Double) -> String {
        String(format: "%.1f 回", value)
    }

    static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) 秒" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    /// 「朝 3/4」のように、種別ごとの件数を添える。
    static func fraction(_ numerator: Int, of denominator: Int) -> String {
        "\(numerator) / \(denominator)"
    }
}
