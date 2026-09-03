import Foundation

/// 会話の 1 文。文言はすべてここに集約し、View と ViewModel と FlowMachine に直書きしない。
public struct CopyLine: Sendable, Equatable, Hashable, Codable {
    /// 文言。`{{topic}}` と `{{time}}` は差し込み位置。
    public let text: String
    /// Guardrails の形式規則をどれで検査するか。
    public let form: Guardrails.Form

    public init(_ text: String, _ form: Guardrails.Form) {
        self.text = text
        self.form = form
    }

    /// 差し込み位置を含むか。
    public var hasPlaceholder: Bool {
        text.contains(DialogueCopy.topicToken) || text.contains(DialogueCopy.timeToken)
    }
}

/// 文言の種類。
public enum CopyKey: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    // 主要 8 文言（毎日出るので 5 種以上の言い換えを持つ。retention R5）
    /// M0 今日いちばん逃げたいことは何？
    case morningAvoidanceQuestion
    /// M1 一番近いのはどれ？
    case morningReasonQuestion
    /// M2 最初の5分でできる、いちばん小さいことは？
    case morningMicroActionQuestion
    /// M3 何時に、どこでやる？
    case morningTimePlaceQuestion
    /// M4 自分に約束してください。
    case morningDeclarationRequest
    /// N1 どうだった？
    case noonStatusQuestion
    /// N2 何が止めてる？
    case noonBlockerQuestion
    /// E0 今日、少しでも前に進めたことは？
    case nightProgressQuestion

    // 分岐・合図の文言
    /// M0 前夜からの引き継ぎ確認。
    case morningCarryoverQuestion
    /// M0 2 日以上空いた後の再入場（retention R4）。
    case morningReentry
    /// M0「特にない」の終わり方（retention R6）。
    case morningGoodDay
    /// M4 受け取りの返事（時刻あり）。
    case morningDeclarationReceipt
    /// M4 受け取りの返事（時刻なし）。
    case morningDeclarationReceiptNoTime
    /// M4「話せない時」モードの選択の促し。
    case morningDeclarationChoice
    /// M4「後で声で」を選んだときの文字入力の促し。
    case morningDeclarationTextPrompt
    /// M4「後で声で」を受けたときの返事（retention R1）。
    case morningDeclarationDeferred
    /// 5 秒沈黙したときの一言（1 回だけ）。
    case silenceNudge
    /// 文字起こしが短すぎたときの再入力。
    case retryPrompt
    /// タイムボックス超過。
    case timeboxExceeded
    /// N0 朝の宣言を返す前の一言。
    case noonIntro
    /// 昼の入口: すでに done。
    case noonAlreadyDone
    /// 昼の入口: 行動時刻より前。
    case noonBeforePlannedTime
    /// 昼の入口: 約束はそのまま。
    case noonPromiseAliveAck
    /// N1「やった」の終わり方。
    case noonDoneEnding
    /// N1「少しやった」の終わり方（前進として残す）。
    case noonPartialEnding
    /// N3 行動を小さくする促し。
    case noonShrinkPrompt
    /// N3 新しい行動を受けたときの返事。
    case noonShrinkAccepted
    /// N3「1 時間後にもう一度」。
    case noonRetryLaterAck
    /// N3「今日は捨てる」。
    case noonDropAck
    /// N3「明日に回す」。
    case noonMoveToTomorrowAck
    /// E0 前進を受けたときの返事。
    case nightProgressAck
    /// E0 前進が無い日（否定的にラベル付けしない）。
    case nightNoProgress
    /// E1 明日はどうする？
    case nightTomorrowQuestion
    /// E1 終わり方。
    case nightEnding
}

/// 全文言と、直近 3 日に使った文言を避ける選択機構。
public enum DialogueCopy {

    /// 本人の名詞（「見積書」「クライアント」）の差し込み位置。
    public static let topicToken = "{{topic}}"
    /// 時刻の差し込み位置。
    public static let timeToken = "{{time}}"

    /// 毎日出るため 5 種以上の言い換えを持つ 8 文言（retention R5）。
    public static let primaryKeys: [CopyKey] = [
        .morningAvoidanceQuestion,
        .morningReasonQuestion,
        .morningMicroActionQuestion,
        .morningTimePlaceQuestion,
        .morningDeclarationRequest,
        .noonStatusQuestion,
        .noonBlockerQuestion,
        .nightProgressQuestion,
    ]

    /// 言い換えの最低数（主要文言）。
    public static let minimumPrimaryVariants = 5

    /// 同じ文言を繰り返さない日数。
    public static let repeatAvoidanceDays = 3

    /// 文言の一覧。
    public static func variants(_ key: CopyKey) -> [CopyLine] {
        switch key {
        case .morningAvoidanceQuestion:
            [
                CopyLine("おはよう。今日、いちばん逃げたいことは何？", .question),
                CopyLine("おはよう。今日、後回しにしそうなことは何？", .question),
                CopyLine("今日、いちばん気が重いことは何？", .question),
                CopyLine("おはよう。今日、目をそらしたいことは何？", .question),
                CopyLine("今日、手をつけたくないことは何？", .question),
                CopyLine("おはよう。今日、避けたいことをひとつ教えて？", .question),
            ]
        case .morningReasonQuestion:
            [
                CopyLine("一番近いのはどれ？", .question),
                CopyLine("気持ちに近いのはどれ？", .question),
                CopyLine("いちばんしっくりくるのはどれ？", .question),
                CopyLine("どれがいちばん近い？", .question),
                CopyLine("近いのはどれだろう？", .question),
            ]
        case .morningMicroActionQuestion:
            [
                CopyLine("最初の5分でできる、いちばん小さいことは？", .question),
                CopyLine("5分で終わる、いちばん小さいことは？", .question),
                CopyLine("最初の5分だけなら、何ができる？", .question),
                CopyLine("いちばん小さい一歩は何？", .question),
                CopyLine("5分だけやるとしたら、何をする？", .question),
            ]
        case .morningTimePlaceQuestion:
            [
                CopyLine("今日は何時に、どこでやる？", .question),
                CopyLine("何時に、どこでやろうか？", .question),
                CopyLine("いつ、どこでやる？", .question),
                CopyLine("何時ごろ、どこでやる？", .question),
                CopyLine("時間と場所を決めよう。何時に、どこで？", .question),
            ]
        case .morningDeclarationRequest:
            [
                CopyLine("じゃあ最後に、自分に約束してください。今日やることを声に出して。", .statement),
                CopyLine("最後にひとつ。今日やることを、自分の声で言ってみて。", .statement),
                CopyLine("今日やることを、自分に向けて声に出して。", .statement),
                CopyLine("自分への約束を、声にして残そう。", .statement),
                CopyLine("最後に、今日やることを声で言ってみて。", .statement),
            ]
        case .noonStatusQuestion:
            [
                CopyLine("どうだった？", .question),
                CopyLine("あれ、どうなった？", .question),
                CopyLine("さっきの約束、どうだった？", .question),
                CopyLine("今日のあれ、どう？", .question),
                CopyLine("あの一歩、どうだった？", .question),
            ]
        case .noonBlockerQuestion:
            [
                CopyLine("何が止めてる？", .question),
                CopyLine("今、何が引っかかってる？", .question),
                CopyLine("何が邪魔してる？", .question),
                CopyLine("止めているのは何？", .question),
                CopyLine("何があると動けない？", .question),
            ]
        case .nightProgressQuestion:
            [
                CopyLine("今日、少しでも前に進めたことは？", .question),
                CopyLine("今日、少しでも動けたことは？", .question),
                CopyLine("今日、ほんの少しでも進んだことは？", .question),
                CopyLine("今日、前に進んだことをひとつ教えて？", .question),
                CopyLine("今日、少しだけできたことは？", .question),
            ]

        case .morningCarryoverQuestion:
            [
                CopyLine("昨日の夜「\(topicToken)」って言ってたね。今日はそれでいく？", .question),
                CopyLine("昨日「\(topicToken)」って話してたね。今日もそれでいく？", .question),
                CopyLine("夜に「\(topicToken)」って言ってた。今日はそれから？", .question),
            ]
        case .morningReentry:
            [
                CopyLine("おかえり。今日から、また一つだけ。", .statement),
                CopyLine("おかえり。今日は、一つだけでいい。", .statement),
                CopyLine("おかえり。また一つだけ、はじめよう。", .statement),
            ]
        case .morningGoodDay:
            [
                CopyLine("それは良い日。10秒で終わるね。", .statement),
                CopyLine("それは良い日。今日はここまで。", .statement),
                CopyLine("いい日だね。10秒で終わり。", .statement),
            ]
        case .morningDeclarationReceipt:
            [
                CopyLine("受け取りました。\(timeToken)に、朝のあなたから届きます。", .statement),
                CopyLine("受け取りました。\(timeToken)に、朝のあなたの声が届きます。", .statement),
            ]
        case .morningDeclarationReceiptNoTime:
            [
                CopyLine("受け取りました。時間になったら、朝のあなたから届きます。", .statement),
            ]
        case .morningDeclarationChoice:
            [
                CopyLine("今、声で言う？ それとも後で？", .question),
            ]
        case .morningDeclarationTextPrompt:
            [
                CopyLine("今日やることを、文字で書いておこう。", .statement),
            ]
        case .morningDeclarationDeferred:
            [
                CopyLine("わかった。一人になれる時間に、もう一度だけ声をかけるね。", .statement),
            ]
        case .silenceNudge:
            [
                CopyLine("長く考えなくていい。10秒で答えて。", .statement),
            ]
        case .retryPrompt:
            [
                CopyLine("もう一度、ゆっくりで大丈夫。", .statement),
            ]
        case .timeboxExceeded:
            [
                CopyLine("続きは昼に聞くね。", .statement),
            ]
        case .noonIntro:
            [
                CopyLine("朝のあなたからです。", .statement),
            ]
        case .noonAlreadyDone:
            [
                CopyLine("今日はもう動けてる。", .statement),
            ]
        case .noonBeforePlannedTime:
            [
                CopyLine("\(timeToken)の約束、まだ生きてる？", .question),
            ]
        case .noonPromiseAliveAck:
            [
                CopyLine("わかった。時間になったら、また声をかけるね。", .statement),
            ]
        case .noonDoneEnding:
            [
                CopyLine("それを残しておくね。", .statement),
            ]
        case .noonPartialEnding:
            [
                CopyLine("それを今日の前進として残すね。", .statement),
            ]
        case .noonShrinkPrompt:
            [
                CopyLine("じゃあ今は\(topicToken)しなくていい。最初の5分でできる、いちばん小さいことは？", .question),
                CopyLine("今日は\(topicToken)を終わらせなくていい。最初の5分でできることは？", .question),
            ]
        case .noonShrinkAccepted:
            [
                CopyLine("わかった。そこまでにしよう。", .statement),
            ]
        case .noonRetryLaterAck:
            [
                CopyLine("わかった。1時間後に、もう一度声をかけるね。", .statement),
            ]
        case .noonDropAck:
            [
                CopyLine("今日はここまで。明日、また一つだけ。", .statement),
            ]
        case .noonMoveToTomorrowAck:
            [
                CopyLine("明日に回そう。朝、また聞くね。", .statement),
            ]
        case .nightProgressAck:
            [
                CopyLine("それを今日の前進として残します。", .statement),
                CopyLine("それを今日の前進として残しておくね。", .statement),
            ]
        case .nightNoProgress:
            [
                CopyLine("今日はそういう日。明日、もっと小さくしよう。", .statement),
            ]
        case .nightTomorrowQuestion:
            [
                CopyLine("明日はどうする？", .question),
                CopyLine("明日はどう動く？", .question),
                CopyLine("明日はどこから始める？", .question),
            ]
        case .nightEnding:
            [
                CopyLine("明日の朝、聞くね。", .statement),
            ]
        }
    }

    /// 差し込み位置を埋める。
    public static func fill(_ line: CopyLine, topic: String = "", time: String = "") -> String {
        fill(line.text, topic: topic, time: time)
    }

    /// 差し込み位置を埋める。
    public static func fill(_ text: String, topic: String = "", time: String = "") -> String {
        text
            .replacingOccurrences(of: topicToken, with: topic)
            .replacingOccurrences(of: timeToken, with: time)
    }

    // MARK: - 選択肢の文言

    /// 企画書 §9 の 6 選択肢。**夜 E0 では使わず**、N3 と翌朝 M0 の引き継ぎ確認で使う。
    public static let sixOptionIDs: [ChoiceID] = [
        .shrinkMore, .dropToday, .moveToTomorrow, .askSomeone, .setDeadline, .differentWay,
    ]

    /// 例示チップ（M2 / N3）。分野に依らない一般形の 4 つ。
    ///
    /// これは「答えに詰まったときの例示」であって選択肢ではない（実装計画 §7.2）。
    /// `label` は画面に出す言葉、`actionText` は行動文として保存する言葉
    /// （行動文は Guardrails の 40 文字以内・動詞終わりを満たす）。
    public static let exampleActionIDs: [ChoiceID] = [
        .exampleOpen, .exampleWriteOneLine, .examplePutOnDesk, .exampleSearchName,
    ]

    /// M3 の時刻の例示。
    public static let timeExampleIDs: [ChoiceID] = [
        .timeInOneHour, .timeAfternoon, .timeEvening, .timePick,
    ]

    /// 選択肢の表示名。
    public static func label(_ id: ChoiceID) -> String {
        switch id {
        case .carryoverKeep: "それでいく"
        case .carryoverChange: "変える"
        case .differentThing: "別のことにする"
        case .shrinkMore: "もっと小さくする"
        case .dropToday: "今日は捨てる"
        case .moveToTomorrow: "明日に回す"
        case .askSomeone: "誰かに頼る"
        case .setDeadline: "期限を決める"
        case .differentWay: "別の方法を考える"
        case .reason(let category): category.displayName
        case .exampleOpen: "開くだけ"
        case .exampleWriteOneLine: "1行だけ書く"
        case .examplePutOnDesk: "必要なものを机に置く"
        case .exampleSearchName: "相手の名前を検索する"
        case .timeInOneHour: "1時間後"
        case .timeAfternoon: "午後"
        case .timeEvening: "夕方"
        case .timePick: "時刻を選ぶ"
        case .declareNow: "今、声で言う"
        case .declareLater: "後で声で"
        case .status(let outcome): outcome.displayName
        case .cannotDecide: "決められない"
        case .retryInOneHour: "1時間後にもう一度"
        case .promiseAlive: "はい"
        case .changeTime: "時間を変える"
        }
    }

    /// 例示チップを選んだときに行動文として保存する言葉。
    ///
    /// 「開くだけ」は画面の言葉で、行動文は「開く」。行動文だけが Guardrails の
    /// 行動文規則（40 文字以内・動詞終わり）に掛かる。
    public static func actionText(_ id: ChoiceID) -> String? {
        switch id {
        case .exampleOpen: "開く"
        case .exampleWriteOneLine: "1行だけ書く"
        case .examplePutOnDesk: "必要なものを机に置く"
        case .exampleSearchName: "相手の名前を検索する"
        default: nil
        }
    }

    /// 検査対象になる全文言（テストで Guardrails を通す）。
    public static var allLines: [CopyLine] {
        CopyKey.allCases.flatMap { variants($0) }
    }
}

/// 直近 `repeatAvoidanceDays` 日に使った文言を避けて選ぶ（retention R5）。
///
/// 乱数を使わないので、同じ入力からは必ず同じ文言が出る（テストで固定できる）。
public struct CopyPicker: Sendable, Equatable, Hashable, Codable {

    /// 1 回の使用。
    public struct Use: Sendable, Equatable, Hashable, Codable {
        public var key: CopyKey
        public var index: Int
        public var day: Int

        public init(key: CopyKey, index: Int, day: Int) {
            self.key = key
            self.index = index
            self.day = day
        }
    }

    /// 通し日番号（`Date` からの変換は呼び出し側が行う）。
    public var day: Int
    /// 使用履歴。
    public var history: [Use]

    public init(day: Int = 0, history: [Use] = []) {
        self.day = day
        self.history = history
    }

    /// 直近 3 日に使っていない言い換えを選び、履歴に積む。
    public mutating func pick(_ key: CopyKey) -> CopyLine {
        let lines = DialogueCopy.variants(key)
        guard !lines.isEmpty else { return CopyLine("", .statement) }

        // 直近 3 日（当日を含めて day-3 以降）に使った言い換えは選ばない。
        let horizon = day - DialogueCopy.repeatAvoidanceDays
        let recent = Set(history.filter { $0.key == key && $0.day >= horizon }.map(\.index))
        let index: Int
        if let fresh = lines.indices.first(where: { !recent.contains($0) }) {
            index = fresh
        } else {
            // すべて直近で使っている場合は、いちばん古く使ったものに戻る。
            let oldest = history
                .filter { $0.key == key }
                .sorted { lhs, rhs in lhs.day == rhs.day ? lhs.index < rhs.index : lhs.day < rhs.day }
                .first
            index = oldest?.index ?? 0
        }

        history.append(Use(key: key, index: index, day: day))
        return lines[index]
    }

    /// 文言そのものを返す（差し込み位置は呼び出し側で埋める）。
    public mutating func pickText(_ key: CopyKey, topic: String = "", time: String = "") -> String {
        DialogueCopy.fill(pick(key), topic: topic, time: time)
    }
}
