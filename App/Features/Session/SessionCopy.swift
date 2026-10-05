import Foundation
import SaydoCore

/// 会話画面（`SessionView` / `ChoiceChipsView` / `TextAnswerField`）でしか使わない文言。
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
    /// `awaitsText` は、いまの質問が文字の答えを待っているか。声を聞いていないのに「聞いています」と言わない。
    static func status(for phase: SessionPhase, awaitsText: Bool) -> String? {
        switch phase {
        case .listening where awaitsText: "入力を待っています"
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
        case .abandoned: "今日は約束を作らずに、ここまで。"
        }
    }

    static let close = "閉じる"
    /// 左上に常にある「閉じる」の VoiceOver ラベル。完了画面の「閉じる」と区別して、会話をやめることを伝える。
    static let closeAccessibilityLabel = "会話を閉じる"

    // MARK: 宣言を確かめる（完了画面。task_038）

    /// いま録った宣言を聞く。
    static let previewDeclaration = "聞いてみる"
    /// 宣言の再生中に、同じボタンで止める。
    static let stopDeclarationPreview = "止める"
    /// 宣言だけを言い直す。1 回の会話で 1 回だけ出す。
    static let retakeDeclaration = "言い直す"
    static let previewDeclarationAccessibilityLabel = "いま録った宣言を聞く"
    static let stopDeclarationPreviewAccessibilityLabel = "宣言の再生を止める"
    static let retakeDeclarationAccessibilityLabel = "宣言を言い直す"
    /// 言い直しを残せなかったとき。最初の宣言が残っていることだけを伝える。
    static let declarationRetakeKept = "うまく録れませんでした。最初の宣言を、そのまま残しています。"

    // MARK: 操作

    /// M0 の文字起こしが違うときの録り直し（retention R7）。
    static let retakeAvoidance = "録り直す"
    /// 右下のキーボードボタン（VoiceOver ラベル）。その質問だけを文字で受ける。次の質問は声に戻る。
    static let keyboardButton = "この質問だけ文字で答える"
    /// 左下の切り替え。読み上げを鳴らさず、文字とチップで答える（retention R1）。
    static let voiceOffToggle = "声を出さない"
    static let voiceOffToggleAccessibilityLabel = "声を出さずに、文字で答える"
    /// 「声を出さない」の間に出す、戻す操作。次の質問から読み上げと声の聞き取りに戻る。
    static let voiceOnToggle = "声に戻す"
    static let voiceOnToggleAccessibilityLabel = "次の質問から、声で答える"

    // MARK: マイクが使えないとき

    static let micDeniedNotice = "マイクを使えない設定になっています。文字で続けられます。"
    static let openSettings = "設定を開く"
    /// マイクの権限はあるのに、声を始められなかったとき。設定の話はしない。
    static let captureFailedNotice = "声をうまく拾えませんでした。この質問は文字で答えられます。"

    // MARK: 文字の入力

    static let textFieldPrompt = "短い言葉で"
    /// 入力欄の VoiceOver ラベル。
    static let textFieldLabel = "文字で答える"
    static let send = "送る"
    /// 必須でない質問（理由・時刻）にだけ出す。
    static let skip = "スキップ"
    static let skipAccessibilityLabel = "この質問をスキップする"

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
