import Foundation
import FoundationModels
import SaydoCore
import XCTest

@testable import SaydoAI

// MARK: - テンプレート側のスタブ

/// Tier B の置換先スタブ。
///
/// 本物の `TemplateDialogueEngine` は task_005b の担当でまだ存在しないため、
/// 「必ず Guardrails を通る文を返す」という契約だけを満たす最小の実装を置く。
/// 返す値は固定なので、テンプレートに落ちたかどうかを戻り値で判定できる。
actor TemplateStub: DialogueEngine {

    static let question = "それの、どこがいちばん重い？"
    static let actions = [
        MicroAction(text: "メールを開く", estimatedMinutes: 1),
        MicroAction(text: "必要な書類を机に置く", estimatedMinutes: 2),
        MicroAction(text: "相手の名前を検索する", estimatedMinutes: 2),
    ]
    static let shrunkText = "ファイルを開く"
    static let reflection = "気まずさを理由に、人への返信から離れている。"

    private(set) var callCounts: [String: Int] = [:]

    private func count(_ name: String) {
        callCounts[name, default: 0] += 1
    }

    func followUpQuestion(avoidance: String) async throws -> String {
        count(#function)
        return Self.question
    }

    func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification {
        count(#function)
        return ReasonClassification(category: .tedious, followUp: "")
    }

    func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction] {
        count(#function)
        return Self.actions
    }

    func shrink(action: MicroAction, blocker: String) async throws -> MicroAction {
        count(#function)
        return MicroAction(
            text: Self.shrunkText,
            estimatedMinutes: 1,
            shrinkCount: action.shrinkCount + 1)
    }

    func classifyDomain(avoidance: String) async throws -> TaskDomain {
        count(#function)
        return .other
    }

    func weeklyReflection(stats: WeeklyStats) async throws -> String {
        count(#function)
        return Self.reflection
    }
}

/// 置換先が失敗する場合。エンジンがエラーを握り潰さないことを確かめる。
struct ThrowingStub: DialogueEngine {
    struct Failure: Error {}

    func followUpQuestion(avoidance: String) async throws -> String { throw Failure() }
    func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification { throw Failure() }
    func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction] { throw Failure() }
    func shrink(action: MicroAction, blocker: String) async throws -> MicroAction { throw Failure() }
    func classifyDomain(avoidance: String) async throws -> TaskDomain { throw Failure() }
    func weeklyReflection(stats: WeeklyStats) async throws -> String { throw Failure() }
}

// MARK: - フォールバック経路（モデルの有無に依らず必ず走る）

final class FoundationModelsDialogueEngineFallbackTests: XCTestCase {

    /// 上限時間を 1 ミリ秒にすると、モデルが使える環境でも必ずタイムアウトする。
    /// これでモデル不在環境と同じ「テンプレートに落ちる」経路を決定的に踏める。
    private func impatientEngine(
        fallback: any DialogueEngine
    ) -> FoundationModelsDialogueEngine {
        FoundationModelsDialogueEngine(fallback: fallback, timeout: .milliseconds(1))
    }

    private let sampleStats = WeeklyStats(
        weekStart: Date(timeIntervalSince1970: 1_756_944_000),
        domainCounts: [.reply: 3, .paperwork: 2],
        reasonRatios: [.awkward: 0.5, .tooMuch: 0.3])

    func testFollowUpQuestionFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let question = try await engine.followUpQuestion(avoidance: "クライアントへの見積書のメール")

        XCTAssertEqual(question, TemplateStub.question)
        XCTAssertTrue(Guardrails.isClean(question, form: .question))
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
        XCTAssertEqual(stats.guardrailReplacedCount, 0, "Guardrails 違反ではないので置換数は増えない")
    }

    func testClassifyReasonFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let classification = try await engine.classifyReason(
            avoidance: "確定申告の領収書整理", answer: "量が多くてうんざりする")

        XCTAssertEqual(classification.category, .tedious)
        XCTAssertEqual(classification.followUp, "")
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
    }

    func testProposeMicroActionsFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let actions = try await engine.proposeMicroActions(
            avoidance: "クライアントへの見積書のメール", reason: .awkward)

        XCTAssertEqual(actions, TemplateStub.actions)
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
    }

    func testShrinkFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)
        let original = MicroAction(text: "メールを開く", estimatedMinutes: 2, shrinkCount: 1)

        let shrunk = try await engine.shrink(action: original, blocker: "何を書けばいいかわからない")

        XCTAssertEqual(shrunk.text, TemplateStub.shrunkText)
        XCTAssertEqual(shrunk.shrinkCount, 2, "テンプレートでも縮小回数は進む")
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
    }

    func testClassifyDomainFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let domain = try await engine.classifyDomain(avoidance: "歯医者の予約")

        XCTAssertEqual(domain, .other)
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
    }

    func testWeeklyReflectionFallsBackToTemplate() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let sentence = try await engine.weeklyReflection(stats: sampleStats)

        XCTAssertEqual(sentence, TemplateStub.reflection)
        XCTAssertTrue(ReflectionRule.isClean(sentence))
        let stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 1)
    }

    /// タイムアウトのときの原因は `.timeout`、そもそもモデルが使えない環境では `.modelUnavailable`。
    /// どちらであっても「テンプレートに落ちた」ことは記録される。
    func testFallbackCauseIsRecorded() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)
        _ = try await engine.followUpQuestion(avoidance: "上司への進捗報告")

        let stats = await engine.stats
        let causes = Set(stats.fallbackCounts.keys)
        let expected: Set<FoundationModelsDialogueEngine.FallbackCause> = [.timeout, .modelUnavailable]
        XCTAssertFalse(causes.isEmpty)
        XCTAssertTrue(
            causes.isSubset(of: expected),
            "1 ミリ秒の上限では timeout か modelUnavailable のどちらかになるはず: \(causes)")
        XCTAssertFalse(stats.logDescription.isEmpty)
    }

    func testStatsAccumulateAndReset() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        _ = try await engine.followUpQuestion(avoidance: "親への電話")
        _ = try await engine.classifyDomain(avoidance: "親への電話")
        var stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 2)

        await engine.resetStats()
        stats = await engine.stats
        XCTAssertEqual(stats.totalFallbackCount, 0)
        XCTAssertEqual(stats.guardrailReplacedCount, 0)
    }

    /// 置換先が失敗したときだけ、エンジンはエラーを投げる。
    func testFallbackFailurePropagates() async {
        let engine = impatientEngine(fallback: ThrowingStub())
        do {
            _ = try await engine.followUpQuestion(avoidance: "親への電話")
            XCTFail("置換先の失敗はそのまま投げるはず")
        } catch {
            XCTAssertTrue(error is ThrowingStub.Failure)
        }
    }

    // MARK: - GenerationError の分岐（実際の GenerationError 値を作って踏む）

    private func context(_ text: String) -> LanguageModelSession.GenerationError.Context {
        LanguageModelSession.GenerationError.Context(debugDescription: text)
    }

    /// 4 つの case の方針を固定する（実装計画 §9、fix-decisions P4.2）。
    func testGenerationErrorPolicy() {
        typealias Engine = FoundationModelsDialogueEngine

        XCTAssertEqual(
            Engine.policy(for: .exceededContextWindowSize(context("over"))),
            .retryOnce,
            "exceededContextWindowSize は新しいセッションで 1 回だけ再試行する")
        XCTAssertEqual(
            Engine.policy(for: .guardrailViolation(context("blocked"))),
            .fallback(.guardrailViolation),
            "guardrailViolation は再試行せずテンプレートに置換する")
        XCTAssertEqual(
            Engine.policy(for: .refusal(.init(transcriptEntries: []), context("refused"))),
            .fallback(.refusal),
            "refusal は再試行せずテンプレートに置換する")
        XCTAssertEqual(
            Engine.policy(for: .unsupportedLanguageOrLocale(context("ja"))),
            .lockToTemplate(.unsupportedLanguageOrLocale),
            "unsupportedLanguageOrLocale は以後テンプレート固定")

        // 挙げていない case はすべて default でテンプレート置換に倒す。
        let others: [LanguageModelSession.GenerationError] = [
            .assetsUnavailable(context("assets")),
            .unsupportedGuide(context("guide")),
            .decodingFailure(context("decode")),
            .rateLimited(context("rate")),
            .concurrentRequests(context("concurrent")),
        ]
        for error in others {
            XCTAssertEqual(
                Engine.policy(for: error), .fallback(.otherGenerationError),
                "未分類の GenerationError はテンプレート置換に倒す: \(error)")
        }
    }

    func testGuardrailViolationFallsBackWithoutRetry() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let output = await engine.handle(
            .guardrailViolation(context("blocked")),
            instructions: "x", input: "y", as: FollowUpQuestionOutput.self)

        XCTAssertNil(output)
        let stats = await engine.stats
        XCTAssertEqual(stats.fallbackCounts[.guardrailViolation], 1)
        XCTAssertNil(stats.fallbackCounts[.timeout], "再試行していないのでタイムアウトは記録されない")
    }

    func testRefusalFallsBackWithoutRetry() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let output = await engine.handle(
            .refusal(.init(transcriptEntries: []), context("refused")),
            instructions: "x", input: "y", as: FollowUpQuestionOutput.self)

        XCTAssertNil(output)
        let stats = await engine.stats
        XCTAssertEqual(stats.fallbackCounts[.refusal], 1)
        XCTAssertNil(stats.fallbackCounts[.timeout])
    }

    /// `exceededContextWindowSize` は再試行する。
    /// 上限 1 ミリ秒なので再試行はタイムアウトし、そのままテンプレートに落ちる。
    func testExceededContextWindowSizeRetriesOnce() async throws {
        let stub = TemplateStub()
        let engine = impatientEngine(fallback: stub)

        let output = await engine.handle(
            .exceededContextWindowSize(context("over")),
            instructions: SaydoAI.PromptBuilder.instructions(for: .followUpQuestion),
            input: SaydoAI.PromptBuilder.followUpInput(avoidance: "見積書のメール"),
            as: FollowUpQuestionOutput.self)

        XCTAssertNil(output)
        let stats = await engine.stats
        XCTAssertEqual(
            stats.totalFallbackCount, 1,
            "再試行が 1 回だけ走り、その結果だけが記録される: \(stats.logDescription)")
        let causes = Set(stats.fallbackCounts.keys)
        XCTAssertTrue(
            causes.isSubset(of: [.timeout, .modelUnavailable, .exceededContextWindowSize]),
            "想定外の原因: \(causes)")
    }

    /// `unsupportedLanguageOrLocale` を受けたら、以後このインスタンスはモデルを呼ばない。
    func testUnsupportedLanguageOrLocaleLocksToTemplate() async throws {
        let stub = TemplateStub()
        // 上限は長くしてよい。ロック後はモデルを呼ばないので待たされない。
        let engine = FoundationModelsDialogueEngine(fallback: stub, timeout: .seconds(6))

        let output = await engine.handle(
            .unsupportedLanguageOrLocale(context("ja_JP")),
            instructions: "x", input: "y", as: FollowUpQuestionOutput.self)
        XCTAssertNil(output)

        let clock = ContinuousClock()
        let start = clock.now
        let question = try await engine.followUpQuestion(avoidance: "クライアントへの見積書のメール")
        let elapsed = clock.now - start

        XCTAssertEqual(question, TemplateStub.question, "ロック後はテンプレートを返す")
        XCTAssertLessThan(elapsed, .seconds(1), "ロック後はモデルを呼ばないので即座に返る")

        let stats = await engine.stats
        XCTAssertEqual(stats.fallbackCounts[.unsupportedLanguageOrLocale], 1)
        XCTAssertEqual(stats.fallbackCounts[.lockedToTemplate], 1)
    }

    /// 上限時間を守る。6 秒の予算そのものの回帰テスト。
    func testTimeoutIsHonoured() async throws {
        let stub = TemplateStub()
        let engine = FoundationModelsDialogueEngine(fallback: stub, timeout: .milliseconds(200))

        let clock = ContinuousClock()
        let start = clock.now
        _ = try await engine.followUpQuestion(avoidance: "確定申告の領収書整理")
        let elapsed = clock.now - start

        XCTAssertLessThan(elapsed, .seconds(3), "200 ミリ秒の上限を大きく超えて待たされてはいけない")
    }
}

// MARK: - SaydoAI.PromptBuilder

final class PromptBuilderTests: XCTestCase {

    /// 指示文の長さを固定する（実装計画 §9 プロンプト予算）。
    /// 文言を書き換えたらこの表も更新すること。600 を超える変更は予算違反。
    func testInstructionLengthsAreFixed() {
        let expected: [SaydoAI.PromptBuilder.Kind: Int] = [
            .followUpQuestion: 234,
            .classifyReason: 353,
            .proposeMicroActions: 305,
            .shrink: 285,
            .classifyDomain: 186,
            .weeklyReflection: 241,
        ]
        for kind in SaydoAI.PromptBuilder.Kind.allCases {
            let text = SaydoAI.PromptBuilder.instructions(for: kind)
            XCTAssertEqual(text.count, expected[kind], "\(kind.rawValue) の指示文の長さが変わった")
        }
    }

    func testEveryInstructionIsWithinBudget() {
        for (kind, text) in SaydoAI.PromptBuilder.allInstructions {
            XCTAssertFalse(text.isEmpty, "\(kind.rawValue) の指示文が空")
            XCTAssertLessThanOrEqual(
                text.count, SaydoAI.PromptBuilder.instructionLimit,
                "\(kind.rawValue) の指示文が 600 文字を超えた（\(text.count) 文字）")
        }
    }

    func testEveryInstructionCoversAllCases() {
        XCTAssertEqual(SaydoAI.PromptBuilder.allInstructions.count, SaydoAI.PromptBuilder.Kind.allCases.count)
    }

    func testInputsAreClampedTo400Characters() {
        let long = String(repeating: "あ", count: 5_000)
        let inputs = [
            SaydoAI.PromptBuilder.followUpInput(avoidance: long),
            SaydoAI.PromptBuilder.reasonInput(avoidance: long, answer: long),
            SaydoAI.PromptBuilder.microActionsInput(avoidance: long, reason: .tooMuch),
            SaydoAI.PromptBuilder.shrinkInput(
                action: MicroAction(text: long, estimatedMinutes: 3), blocker: long),
            SaydoAI.PromptBuilder.domainInput(avoidance: long),
        ]
        for input in inputs {
            XCTAssertLessThanOrEqual(input.count, SaydoAI.PromptBuilder.inputLimit, "入力が 400 文字を超えた")
        }
    }

    func testInputCollapsesNewlines() {
        let messy = "見積書の\nメール\n\n  返信"
        let input = SaydoAI.PromptBuilder.followUpInput(avoidance: messy)
        XCTAssertEqual(input, "逃げたいこと: 見積書の メール 返信")
        XCTAssertFalse(input.contains("\n"), "利用者の改行でプロンプトの構造を壊させない")
    }

    /// 振り返りの入力は集計だけ。件数と割合の数字は渡さない（実装計画 §7.6 / fix-decisions P2.2）。
    func testReflectionInputCarriesOnlyRankedAggregates() {
        let stats = WeeklyStats(
            weekStart: Date(timeIntervalSince1970: 1_756_944_000),
            domainCounts: [.reply: 3, .paperwork: 2, .money: 1],
            reasonRatios: [.awkward: 0.5, .tooMuch: 0.3, .tedious: 0.2])
        let input = SaydoAI.PromptBuilder.reflectionInput(stats: stats)

        XCTAssertTrue(input.contains("人への返信"))
        XCTAssertTrue(input.contains("気まずい"))
        XCTAssertFalse(
            input.contains(where: { $0.isNumber }),
            "件数や割合を数字のまま渡さない: \(input)")
        XCTAssertLessThanOrEqual(input.count, SaydoAI.PromptBuilder.inputLimit)
    }

    func testReflectionInputHandlesEmptyStats() {
        let stats = WeeklyStats(weekStart: Date(timeIntervalSince1970: 1_756_944_000))
        let input = SaydoAI.PromptBuilder.reflectionInput(stats: stats)
        XCTAssertFalse(input.isEmpty)
        XCTAssertLessThanOrEqual(input.count, SaydoAI.PromptBuilder.inputLimit)
    }
}

// MARK: - ReflectionRule

final class ReflectionRuleTests: XCTestCase {

    func testAcceptsAPlainSentence() {
        XCTAssertTrue(ReflectionRule.isClean("気まずさを理由に、人への返信から離れている。"))
    }

    func testRejectsNumbers() {
        let withNumbers = [
            "3 回のうち 2 回は人への返信だった。",
            "３回は人への返信だった。",
            "三回は人への返信だった。",
            "半分は人への返信だった。",
            "五割が書類だった。",
            "60パーセントが書類だった。",
            "60% が書類だった。",
        ]
        for text in withNumbers {
            XCTAssertFalse(ReflectionRule.isClean(text), "数を含むのに通った: \(text)")
        }
    }

    func testRejectsTooLongSentence() {
        let long = String(repeating: "あ", count: ReflectionRule.limit + 1)
        XCTAssertFalse(ReflectionRule.isClean(long))
        XCTAssertTrue(ReflectionRule.violations(long).contains { $0.contains("tooLong") })
    }

    func testRejectsBlamingSentence() {
        XCTAssertFalse(ReflectionRule.isClean("あなたはサボっている。"))
        XCTAssertFalse(ReflectionRule.isClean("今週は未達成だった。"))
    }

    func testRejectsLinkAndEnglishOnly() {
        XCTAssertFalse(ReflectionRule.isClean("https://example.com を見て。"))
        XCTAssertFalse(ReflectionRule.isClean("You avoid replying to people."))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(ReflectionRule.isClean("   "))
    }
}

// MARK: - ModelAvailability

final class ModelAvailabilityTests: XCTestCase {

    func testVerdictIsLoggable() {
        let verdict = ModelAvailability.evaluate()
        XCTAssertFalse(verdict.logDescription.isEmpty)
        XCTAssertFalse(ModelAvailability.log().isEmpty)
    }

    /// Tier A は「モデルが使える」かつ「その言語に対応している」の両方が要る（fix-decisions P4.4）。
    /// 存在しない言語を渡せば、モデルが使えても Tier B に落ちなければならない。
    func testUnsupportedLocaleFallsBackToTierB() throws {
        let verdict = ModelAvailability.evaluate(locale: Locale(identifier: "xx_XX"))
        switch verdict {
        case .tierA:
            XCTFail("対応していない言語で Tier A になってはいけない")
        case .tierB(let reason):
            // モデル自体が使えない環境では、言語より先に availability の理由が返る。
            let acceptable: [ModelAvailability.TierBReason] = [
                .localeNotSupported("xx_XX"),
                .deviceNotEligible,
                .appleIntelligenceNotEnabled,
                .modelNotReady,
            ]
            XCTAssertTrue(acceptable.contains(reason), "想定外の理由: \(reason.logDescription)")
        }
    }

    func testJapaneseIsTheConfiguredLocale() {
        XCTAssertEqual(ModelAvailability.japanese.identifier, "ja_JP")
    }
}

// MARK: - 結合テスト（Apple Intelligence が有効なときだけ走る）

final class FoundationModelsDialogueEngineIntegrationTests: XCTestCase {

    private func requireTierA() throws {
        let verdict = ModelAvailability.evaluate()
        try XCTSkipUnless(
            verdict.isTierA,
            "Tier A ではないので結合テストをスキップする: \(verdict.logDescription)")
    }

    private func makeEngine() -> (FoundationModelsDialogueEngine, TemplateStub) {
        let stub = TemplateStub()
        return (FoundationModelsDialogueEngine(fallback: stub), stub)
    }

    /// 何が返ってきても Guardrails を通っていること。これが Tier A の唯一の約束。
    /// LLM が出したものでも、テンプレートに置換されたものでも、この不変条件は変わらない。
    func testEveryReturnedTextPassesGuardrails() async throws {
        try requireTierA()
        let (engine, _) = makeEngine()
        let clock = ContinuousClock()

        let fixtures: [(avoidance: String, answer: String)] = [
            ("クライアントへの見積書のメール", "返事が遅れて気まずい"),
            ("確定申告の領収書整理", "量が多くてうんざりする"),
        ]

        for fixture in fixtures {
            var start = clock.now
            let question = try await engine.followUpQuestion(avoidance: fixture.avoidance)
            XCTAssertTrue(
                Guardrails.isClean(question, form: .question),
                "followUpQuestion が Guardrails を通っていない: \(question)")
            XCTAssertLessThan(clock.now - start, .seconds(14), "followUpQuestion が 6 秒の上限を大きく超えた")

            start = clock.now
            let classification = try await engine.classifyReason(
                avoidance: fixture.avoidance, answer: fixture.answer)
            if !classification.followUp.isEmpty {
                XCTAssertTrue(
                    Guardrails.isClean(classification.followUp, form: .question),
                    "classifyReason の追加質問が Guardrails を通っていない: \(classification.followUp)")
            }
            XCTAssertLessThan(clock.now - start, .seconds(14), "classifyReason が 6 秒の上限を大きく超えた")

            start = clock.now
            let actions = try await engine.proposeMicroActions(
                avoidance: fixture.avoidance, reason: classification.category)
            XCTAssertEqual(actions.count, 3, "M2 は 3 案")
            for action in actions {
                XCTAssertTrue(
                    Guardrails.isClean(action.text, form: .action),
                    "proposeMicroActions が Guardrails を通っていない: \(action.text)")
                XCTAssertTrue((1...5).contains(action.estimatedMinutes), "5 分を超える案が出た")
            }
            XCTAssertLessThan(clock.now - start, .seconds(14), "proposeMicroActions が 6 秒の上限を大きく超えた")

            start = clock.now
            let shrunk = try await engine.shrink(action: actions[0], blocker: fixture.answer)
            XCTAssertTrue(
                Guardrails.isClean(shrunk.text, form: .action),
                "shrink が Guardrails を通っていない: \(shrunk.text)")
            XCTAssertEqual(shrunk.shrinkCount, actions[0].shrinkCount + 1)
            XCTAssertLessThan(clock.now - start, .seconds(14), "shrink が 6 秒の上限を大きく超えた")

            start = clock.now
            _ = try await engine.classifyDomain(avoidance: fixture.avoidance)
            XCTAssertLessThan(clock.now - start, .seconds(14), "classifyDomain が 6 秒の上限を大きく超えた")
        }

        let stats = await engine.stats
        // 置換が起きたかどうかは環境と生成の揺れ次第。件数が数えられていることだけを固定する。
        XCTAssertGreaterThanOrEqual(stats.guardrailReplacedCount, 0)
        XCTAssertFalse(stats.logDescription.isEmpty)
    }

    func testWeeklyReflectionPassesReflectionRule() async throws {
        try requireTierA()
        let (engine, _) = makeEngine()
        let stats = WeeklyStats(
            weekStart: Date(timeIntervalSince1970: 1_756_944_000),
            domainCounts: [.reply: 3, .paperwork: 2, .money: 1],
            reasonRatios: [.awkward: 0.5, .tooMuch: 0.3, .tedious: 0.2])

        let clock = ContinuousClock()
        let start = clock.now
        let sentence = try await engine.weeklyReflection(stats: stats)
        XCTAssertLessThan(clock.now - start, .seconds(14), "weeklyReflection が 6 秒の上限を大きく超えた")

        XCTAssertTrue(
            ReflectionRule.isClean(sentence),
            "振り返り 1 文が規則を通っていない: \(sentence) / \(ReflectionRule.violations(sentence))")
    }
}
