import Foundation

/// オンボーディングの文言（実装計画 §17.6、task_056）。3 画面: 何をするアプリか、マイク、アラーム。
///
/// 画面ファイルに日本語を直書きしない（CLAUDE.md §1）。
/// 責める語彙を置かない（企画原則 §22-1）。権限を断った人にも同じ調子で話す。
enum OnboardingCopy {

    // MARK: - 共通

    static let next = "次へ"
    static let back = "戻る"
    static let openSystemSettings = "設定を開く"

    // MARK: - 何をするアプリか

    static let conceptTitle = "SAYDO"
    static let conceptBody = "今日の約束を声にして、やるまで追いかけてもらう。"
    static let conceptDetail = "約束と、最初にやることを話します。決めた時刻から、アプリで答えるまでアラームが鳴ります。"

    // MARK: - マイク

    static let microphoneTitle = "あなたの声を録ります"
    static let microphoneBody = "録った声はこの端末の中だけに置き、アラームの音としてあなた自身に返します。"
    static let microphoneRequest = "マイクを許可する"
    static let microphoneGranted = "マイクを使えます。"
    static let microphoneDenied = "マイクは使わないままでも、文字だけで約束できます。"
    static let microphoneDeniedHint = "あとで声を使いたくなったら、設定アプリから変えられます。"

    // MARK: - アラーム

    static let alarmTitle = "アラームで追いかけます"
    static let alarmBody = "約束の時刻から 3 分おきに鳴ります。アプリを開いて答えると止まります。"
    static let alarmDetail = "許可しない場合、約束は残りますがアラームは鳴りません。あとで設定アプリから変えられます。"
    static let alarmRequest = "アラームを許可する"
}
