import Foundation
import FoundationModels
import SaydoCore

/// 呼び出しが上限時間内に返らなかったことを表す。
struct CallTimedOut: Error {}

/// 先に届いた 1 件だけを通す受け口。2 件目以降は捨てる。
private actor FirstOutcome<Value: Sendable> {
    private var outcome: Result<Value, any Error>?
    private var waiter: CheckedContinuation<Result<Value, any Error>, Never>?

    func deliver(_ result: Result<Value, any Error>) {
        guard outcome == nil else { return }
        outcome = result
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: result)
        }
    }

    func wait() async -> Result<Value, any Error> {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            if let outcome {
                continuation.resume(returning: outcome)
            } else {
                waiter = continuation
            }
        }
    }
}

/// 上限時間つきで実行する。時間切れなら `CallTimedOut` を投げる。
///
/// **打ち切った処理の完了を待たない**。`withThrowingTaskGroup` で組むと、
/// 時間切れで抜けるときにグループが子タスクの終了を待つため、
/// キャンセルに応じない処理では上限時間が意味を失う。
/// 実測（macOS 26.5 / M4）: グループ版では 6 秒で打ち切ったはずの `classifyDomain` が
/// 実際には 44 秒返らなかった。Foundation Models の生成はキャンセルしても即座には止まらない。
///
/// ここでは上限を「利用者を待たせない上限」と定義し、放棄した生成はそのまま走らせる。
/// 放棄した生成がモデルを占有している間、次の呼び出しも上限まで待たされてテンプレートに落ちうる。
/// 会話を止めないことを優先する（実装計画 §7.2）。
func withTimeout<Value: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let gate = FirstOutcome<Value>()

    let work = Task {
        do {
            await gate.deliver(.success(try await operation()))
        } catch {
            await gate.deliver(.failure(error))
        }
    }
    let timer = Task {
        do {
            try await Task.sleep(for: duration)
            await gate.deliver(.failure(CallTimedOut()))
        } catch {
            // 本処理が先に終わってキャンセルされた。
        }
    }

    let outcome = await gate.wait()
    timer.cancel()
    // キャンセルを試みるだけで、終了は待たない。
    work.cancel()
    return try outcome.get()
}

/// Tier A の `DialogueEngine`。オンデバイス LLM（Foundation Models）で穴埋めする。
///
/// 設計（実装計画 §7.2・§9、fix-decisions P4.2 / P4.3 / P4.4）:
///
/// - **1 呼び出し 1 セッション**。会話履歴を渡さないのでセッションを使い回す理由がなく、
///   セッション上限 4,096 トークンにも近づかない。
/// - **6 秒タイムアウト**。超えたらテンプレートに落として会話を止めない。
/// - **出力は必ず SaydoCore の `Guardrails` を通す**。違反したらテンプレートに置換し、
///   `stats.guardrailReplacedCount` を増やす（`SessionLog.guardrailReplacedCount` に積む値）。
/// - `LanguageModelSession.GenerationError` の扱い:
///   `exceededContextWindowSize` は新しいセッションで 1 回だけ再試行、
///   `guardrailViolation` と `refusal` はテンプレート置換（再試行しない）、
///   `unsupportedLanguageOrLocale` はこのインスタンスを以後テンプレート固定にする。
///   それ以外は `default` でテンプレート置換に倒す。
///
/// 失敗経路は **すべて `fallback`（Tier B の `DialogueEngine`）へ委譲する**。
/// 例外を投げるのは `fallback` 自身が投げたときだけで、このクラスは会話を止めない。
public actor FoundationModelsDialogueEngine: DialogueEngine {

    /// テンプレートへ落ちた原因。原因別に数えて Phase 2 の品質計測に使う（実装計画 §0.3）。
    public enum FallbackCause: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        /// 起動時点で Tier B（Apple Intelligence 非対応 / 無効 / 日本語非対応）。
        case modelUnavailable
        /// `unsupportedLanguageOrLocale` を受けて以後テンプレート固定。
        case lockedToTemplate
        /// 6 秒タイムアウト。
        case timeout
        /// SaydoCore の `Guardrails` 違反（禁止句・文字数・形式）。
        case guardrail
        /// Apple 側のセーフティガードレール。
        case guardrailViolation
        /// モデルが応答を拒否した。
        case refusal
        /// 再試行してもセッション上限を超えた。
        case exceededContextWindowSize
        /// この言語・地域に対応していない。
        case unsupportedLanguageOrLocale
        /// 上記以外の `GenerationError`。
        case otherGenerationError
        /// `GenerationError` でないエラー。
        case otherError
    }

    /// 置換の集計。
    public struct Stats: Sendable, Equatable {
        /// `Guardrails` 違反でテンプレートに置換した回数。
        public var guardrailReplacedCount: Int
        /// 原因別のテンプレート置換回数。
        public var fallbackCounts: [FallbackCause: Int]

        public init(guardrailReplacedCount: Int = 0, fallbackCounts: [FallbackCause: Int] = [:]) {
            self.guardrailReplacedCount = guardrailReplacedCount
            self.fallbackCounts = fallbackCounts
        }

        /// テンプレートに落ちた総数。
        public var totalFallbackCount: Int {
            fallbackCounts.values.reduce(0, +)
        }

        /// 原因別の内訳を 1 行にする。ログと開発者向け表示に使う。
        public var logDescription: String {
            let breakdown = fallbackCounts
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: " ")
            return "fallback=\(totalFallbackCount) guardrailReplaced=\(guardrailReplacedCount) [\(breakdown)]"
        }
    }

    private let fallback: any DialogueEngine
    private let model: SystemLanguageModel
    private let locale: Locale
    private let timeout: Duration

    /// `unsupportedLanguageOrLocale` を受けたらここが true になり、以後モデルを呼ばない。
    private var lockedToTemplate = false

    /// 置換の集計。読み出しは `await engine.stats`。
    public private(set) var stats = Stats()

    /// - Parameters:
    ///   - fallback: 置換先。Tier B の `TemplateDialogueEngine`（task_005b）を渡す。
    ///   - model: 使うモデル。既定は `SystemLanguageModel.default`。
    ///   - locale: 会話の言語。既定は `ja_JP`。
    ///   - timeout: 1 呼び出しの上限時間。既定は 6 秒（実装計画 §7.2）。
    public init(
        fallback: any DialogueEngine,
        model: SystemLanguageModel = .default,
        locale: Locale = ModelAvailability.japanese,
        timeout: Duration = .seconds(6)
    ) {
        self.fallback = fallback
        self.model = model
        self.locale = locale
        self.timeout = timeout
    }

    /// この時点の Tier 判定。
    public nonisolated var availability: ModelAvailability.Verdict {
        ModelAvailability.evaluate(model: model, locale: locale)
    }

    /// 集計をゼロに戻す。セッションの区切りで呼ぶ。
    public func resetStats() {
        stats = Stats()
    }

    // MARK: - DialogueEngine

    public func followUpQuestion(avoidance: String) async throws -> String {
        guard let output = await generate(
            kind: .followUpQuestion,
            input: PromptBuilder.followUpInput(avoidance: avoidance),
            as: FollowUpQuestionOutput.self)
        else {
            return try await fallback.followUpQuestion(avoidance: avoidance)
        }

        let question = output.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Guardrails.isClean(question, form: .question) else {
            recordGuardrailReplacement()
            return try await fallback.followUpQuestion(avoidance: avoidance)
        }
        return question
    }

    public func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification {
        guard let output = await generate(
            kind: .classifyReason,
            input: PromptBuilder.reasonInput(avoidance: avoidance, answer: answer),
            as: ReasonClassificationOutput.self)
        else {
            return try await fallback.classifyReason(avoidance: avoidance, answer: answer)
        }

        let classification = output.domainValue
        let followUp = classification.followUp.trimmingCharacters(in: .whitespacesAndNewlines)

        // 分類は列挙なので必ず妥当。追加質問だけが自由文で、そこだけが違反しうる。
        // 違反したときに分類まで捨てると M1 の価値が消えるので、
        // **追加質問の文だけ** をテンプレート（fallback の追加質問）に置換し、分類は残す。
        guard Guardrails.isClean(followUp, form: .question) else {
            recordGuardrailReplacement()
            let template = try await fallback.classifyReason(avoidance: avoidance, answer: answer)
            return ReasonClassification(category: classification.category, followUp: template.followUp)
        }
        return ReasonClassification(category: classification.category, followUp: followUp)
    }

    public func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction] {
        guard let output = await generate(
            kind: .proposeMicroActions,
            input: PromptBuilder.microActionsInput(avoidance: avoidance, reason: reason),
            as: MicroActionProposal.self)
        else {
            return try await fallback.proposeMicroActions(avoidance: avoidance, reason: reason)
        }

        let actions = output.actions.map { $0.domainValue() }
        // M2 の出力は 3 件で 1 つの提示。1 件でも違反したらステップごとテンプレートに置換する
        // （実装計画 §7.5「該当ステップのテンプレート文に置換」）。
        let isClean = actions.count == 3 && actions.allSatisfy(isAcceptable)
        guard isClean else {
            recordGuardrailReplacement()
            return try await fallback.proposeMicroActions(avoidance: avoidance, reason: reason)
        }
        return actions
    }

    public func shrink(action: MicroAction, blocker: String) async throws -> MicroAction {
        guard let output = await generate(
            kind: .shrink,
            input: PromptBuilder.shrinkInput(action: action, blocker: blocker),
            as: MicroActionOutput.self)
        else {
            return try await fallback.shrink(action: action, blocker: blocker)
        }

        let shrunk = output.domainValue(shrinkCount: action.shrinkCount + 1)
        guard isAcceptable(shrunk) else {
            recordGuardrailReplacement()
            return try await fallback.shrink(action: action, blocker: blocker)
        }
        return shrunk
    }

    public func classifyDomain(avoidance: String) async throws -> TaskDomain {
        guard let output = await generate(
            kind: .classifyDomain,
            input: PromptBuilder.domainInput(avoidance: avoidance),
            as: TaskDomainOutput.self)
        else {
            return try await fallback.classifyDomain(avoidance: avoidance)
        }
        // 列挙なので自由文の検査対象が無い。Guardrails は文にしか適用できない。
        return output.domainValue
    }

    public func weeklyReflection(stats weekly: WeeklyStats) async throws -> String {
        guard let output = await generate(
            kind: .weeklyReflection,
            input: PromptBuilder.reflectionInput(stats: weekly),
            as: ReflectionOutput.self)
        else {
            return try await fallback.weeklyReflection(stats: weekly)
        }

        let sentence = output.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReflectionRule.isClean(sentence) else {
            recordGuardrailReplacement()
            return try await fallback.weeklyReflection(stats: weekly)
        }
        return sentence
    }

    // MARK: - 生成

    /// モデルを 1 回呼ぶ。失敗はここで全部飲み込み、nil を返して呼び出し側をテンプレートに倒す。
    private func generate<Output: Generable & Sendable>(
        kind: PromptBuilder.Kind,
        input: String,
        as type: Output.Type
    ) async -> Output? {
        if lockedToTemplate {
            record(.lockedToTemplate)
            return nil
        }
        guard ModelAvailability.evaluate(model: model, locale: locale).isTierA else {
            record(.modelUnavailable)
            return nil
        }

        let instructions = PromptBuilder.instructions(for: kind)
        do {
            return try await respond(instructions: instructions, input: input, as: type)
        } catch is CallTimedOut {
            record(.timeout)
            return nil
        } catch let error as LanguageModelSession.GenerationError {
            return await handle(error, instructions: instructions, input: input, as: type)
        } catch {
            record(.otherError)
            return nil
        }
    }

    /// `GenerationError` を受けたときの方針（実装計画 §9、fix-decisions P4.2）。
    enum ErrorPolicy: Sendable, Equatable {
        /// 新しい `LanguageModelSession` で 1 回だけ再試行する。
        case retryOnce
        /// テンプレートに置換して会話を続ける（再試行しない）。
        case fallback(FallbackCause)
        /// テンプレートに置換し、以後このインスタンスをテンプレート固定にする。
        case lockToTemplate(FallbackCause)
    }

    /// エラーごとの方針。モデルが無くてもテストできるように純関数にしてある。
    ///
    /// ここに書いた case 名はすべて macOS 26.2 SDK の `FoundationModels.swiftinterface` に実在し、
    /// 本パッケージのビルドで実際にコンパイルが通っている。未確認の case 名は書かず `default` で受ける。
    static func policy(for error: LanguageModelSession.GenerationError) -> ErrorPolicy {
        switch error {
        case .exceededContextWindowSize:
            .retryOnce
        case .guardrailViolation:
            .fallback(.guardrailViolation)
        case .refusal:
            .fallback(.refusal)
        case .unsupportedLanguageOrLocale:
            .lockToTemplate(.unsupportedLanguageOrLocale)
        default:
            .fallback(.otherGenerationError)
        }
    }

    /// `GenerationError` の分岐。`internal` なのはテストから直接踏むため。
    func handle<Output: Generable & Sendable>(
        _ error: LanguageModelSession.GenerationError,
        instructions: String,
        input: String,
        as type: Output.Type
    ) async -> Output? {
        switch Self.policy(for: error) {
        case .retryOnce:
            do {
                return try await respond(instructions: instructions, input: input, as: type)
            } catch is CallTimedOut {
                record(.timeout)
                return nil
            } catch {
                record(.exceededContextWindowSize)
                return nil
            }

        case .fallback(let cause):
            record(cause)
            return nil

        case .lockToTemplate(let cause):
            lockedToTemplate = true
            record(cause)
            return nil
        }
    }

    /// 1 呼び出し 1 セッション + 6 秒タイムアウト。
    private func respond<Output: Generable & Sendable>(
        instructions: String,
        input: String,
        as type: Output.Type
    ) async throws -> Output {
        let model = self.model
        let limit = PromptBuilder.responseTokenLimit
        return try await withTimeout(timeout) {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: input,
                generating: type,
                options: GenerationOptions(maximumResponseTokens: limit))
            return response.content
        }
    }

    // MARK: - 検査と集計

    /// 行動文が Guardrails と 5 分以下の条件を満たすか。
    private func isAcceptable(_ action: MicroAction) -> Bool {
        Guardrails.isClean(action.text, form: .action)
            && action.isFiveMinutesOrLess
            && action.estimatedMinutes >= 1
    }

    private func recordGuardrailReplacement() {
        stats.guardrailReplacedCount += 1
        record(.guardrail)
    }

    private func record(_ cause: FallbackCause) {
        stats.fallbackCounts[cause, default: 0] += 1
    }
}

/// 週次振り返り 1 文の追加規則（実装計画 §7.5）。
///
/// SaydoCore の `Guardrails.Form.statement` は禁止句・URL・日本語の検査までを担い、
/// 「80 文字以内」「数字を含まない」は課さない（`Form` は 3 種で固定されている）。
/// SaydoCore は task_005 の担当で本タスクでは変更しないため、
/// 振り返り固有の 2 条件だけをここで足し、禁止句などは `Guardrails` に委ねる。
public enum ReflectionRule {

    /// 振り返り 1 文の上限文字数。
    public static let limit = 80

    /// 使ってはいけない数の表記（アラビア数字・全角数字・漢数字と割合の語）。
    static let forbiddenCounters: [Character] = Array(
        "0123456789０１２３４５６７８９一二三四五六七八九十％%")

    /// 数を表す語（文字単位では拾えないもの）。
    static let forbiddenWords = ["半分", "割", "パーセント"]

    /// 検査を通るか。
    public static func isClean(_ text: String) -> Bool {
        violations(text).isEmpty
    }

    /// 違反の説明。空なら合格。
    public static func violations(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [String] = []

        found.append(contentsOf: Guardrails.check(trimmed, form: .statement).map { String(describing: $0) })

        if trimmed.count > limit {
            found.append("tooLong(limit: \(limit), actual: \(trimmed.count))")
        }
        if trimmed.contains(where: { forbiddenCounters.contains($0) }) {
            found.append("containsNumber")
        }
        for word in forbiddenWords where trimmed.contains(word) {
            found.append("containsNumberWord(\(word))")
        }
        return found
    }
}
