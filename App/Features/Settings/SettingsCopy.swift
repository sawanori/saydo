import Foundation

/// 設定画面の文言（実装計画 §8・§17）。
///
/// 画面ファイルに日本語を直書きしない（CLAUDE.md §1）。
/// 「未達成」「失敗」を項目名に使わない（企画原則 §22-1・§22-7）。
enum SettingsCopy {

    static let title = "設定"
    static let close = "閉じる"

    // MARK: - 追いかける時刻

    static let roundTimesSection = "追いかける時刻"
    static let morningTimeLabel = "朝"
    static let noonTimeLabel = "昼"
    static let nightTimeLabel = "晩"
    static let roundTimesFootnote = "約束した日は、この時刻に約束の声のアラームが鳴ります。アプリで答えるまで、朝・昼・晩と追いかけます。"

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
    static let deleteConfirmMessage = "音声も、約束も、記録も戻せません。書き出しておくと手元に残せます。"
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
    static let outcomeLabel = "約束のあとの答え"
    static let voicelessLabel = "声を使わずに約束した回数"
    static let noCommitmentDaysLabel = "約束をしなかった日"

    static func developerWindow(days: Int) -> String {
        "直近 \(days) 日"
    }

    static func count(_ value: Int) -> String {
        "\(value) 件"
    }

    static func days(_ value: Int) -> String {
        "\(value) 日"
    }
}
