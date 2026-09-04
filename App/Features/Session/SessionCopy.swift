import Foundation
import SaydoCore

/// 会話画面（`SessionView` / `ChoiceChipsView` / `TextFallbackSheet`）でしか使わない文言。
///
/// 会話の中身（質問・返事）は `SaydoCore.DialogueCopy` が持つ。ここに置くのは
/// ボタンのラベル・状態行・アクセシビリティ文言といった **画面固有の言葉** だけ
/// （CLAUDE.md §1「ユーザー向け文言は `*Copy` に置く」）。
///
/// 責める言葉・達成マーク・連続日数を 1 つも置かない（企画原則 §22-1 / §22-8）。
enum SessionCopy {

    /// 画面上部のロゴ。
    static let logo = "SAYDO"

    // MARK: 状態行

    /// いまの状態を 1 行で伝える。読み上げ中と選択待ちは何も出さない（画面を静かに保つ）。
    static func status(for phase: SessionPhase) -> String? {
        switch phase {
        case .listening: "聞いています…"
        case .thinking: "考えています…"
        case .recordingDeclaration: "録音しています…"
        case .playback: "再生しています…"
        case .idle, .speaking, .choosing, .done, .error: nil
        }
    }

    // MARK: 終わり

    /// 会話の終わり方に応じた締めの 1 行。どの終わり方も否定的にラベル付けしない。
    static func closing(for completion: FlowCompletion) -> String {
        switch completion {
        case .completed: "今日はここまで。"
        case .goodDay: "良い日を。"
        case .suspended, .timeboxExceeded: "続きは、また。"
        }
    }

    static let close = "閉じる"

    // MARK: 操作

    /// M0 の文字起こしが違うときの録り直し（retention R7）。
    static let retakeAvoidance = "録り直す"
    /// 右下のキーボードボタン。
    static let keyboardButton = "キーボードで答える"
    /// 「話せない時」モードへの切り替え（retention R1）。
    static let voicelessToggle = "話せない時"

    // MARK: マイクが使えないとき

    static let micDeniedNotice = "マイクを使えない設定になっています。文字で続けられます。"
    static let openSettings = "設定を開く"

    // MARK: 例示と短文入力

    /// 例示（チップではない）の区切り。
    static let exampleSeparator = "　／　"
    static let textFieldPrompt = "短い言葉で"
    static let send = "送る"
    static let skip = "スキップ"
    static let textSheetTitle = "文字で答える"

    // MARK: アクセシビリティ

    static let waveformLabel = "声の波形"
    static let declarationLabel = "朝のあなたの言葉"
}

/// アプリの外枠（`RootView`）の文言。
///
/// タブ名は統合後も残る。「今日」「記録」タブの中身は統合時に `TodayView`（F）と
/// `TimelineView`（B）に差し替わるため、プレースホルダの文言はそこで消える。
enum RootCopy {
    static let todayTab = "今日"
    static let timelineTab = "記録"
    /// 「今日」タブのプレースホルダ。
    static let speakNow = "今話す"
    /// 「記録」タブのプレースホルダ。
    static let timelineEmpty = "ここに、あなたの声が残ります。"
    /// オンボーディングのプレースホルダ。
    static let onboardingLead = "逃げたいことを声にして、5 分だけ動く。"
    static let onboardingStart = "はじめる"
    /// 会話の支度をしている 1 フレーム。
    static let preparing = "はじめます"
}
