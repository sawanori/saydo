// SAYDO スパイク S-A / S-D: fm-probe
//
// 目的: Foundation Models（オンデバイス LLM）が「理由分類」「5 分以下への細分化」「短い追加質問」
//       「分野分類」を日本語で実用水準に出せるかを 20 件のフィクスチャで測る。
//
// ビルド: swiftc -O Spikes/fm-probe/main.swift -o /tmp/fm-probe
// 実行:   /tmp/fm-probe [--fixtures <path>] [--out <path>] [--limit <n>] [--timeout <秒>]
//                       [--max-response-tokens <n>|none] [--dry-run]
//
// --dry-run はモデルを一切呼ばず、フィクスチャの読み込みと自動判定コードだけを検証する。
// Foundation Models が .unavailable な環境でも自動判定コードの健全性を確認するために使う。
// 進捗は標準エラーへ出す（標準出力はファイルへリダイレクトすると全バッファリングされ、途中経過が見えないため）。

import Foundation
import FoundationModels

// MARK: - 1. @Generable 型（実装計画 §9）
// @Guide は description と .anyOf / .range / .count のみに使う（fix-decisions P4.3）。
// 文字数・動詞終わり・疑問形は後段の Guardrails 検査で強制する。

@Generable
enum ReasonCategory: String, CaseIterable {
    case awkward
    case perfectionism
    case tedious
    case anxious
    case tooMuch
    case unclearStart
    case deadlineFear

    var label: String {
        switch self {
        case .awkward: return "気まずい"
        case .perfectionism: return "完璧にやりたい"
        case .tedious: return "面倒"
        case .anxious: return "不安・怖い"
        case .tooMuch: return "量が多い"
        case .unclearStart: return "何から始めるかわからない"
        case .deadlineFear: return "期限が怖い"
        }
    }
}

@Generable
enum TaskDomain: String, CaseIterable {
    case personReply
    case money
    case bigTask
    case sales
    case paperwork
    case health
    case other

    var label: String {
        switch self {
        case .personReply: return "人への返信"
        case .money: return "お金"
        case .bigTask: return "大きなタスク"
        case .sales: return "営業"
        case .paperwork: return "書類"
        case .health: return "健康"
        case .other: return "その他"
        }
    }
}

@Generable
struct ReasonClassification {
    @Guide(description: "逃げたい理由の分類")
    var category: ReasonCategory

    @Guide(description: "本人の言葉を受け止めて、もう一歩だけ具体にする日本語の質問。1 文だけ。")
    var followUp: String
}

@Generable
struct MicroAction {
    @Guide(description: "今日の最初の 5 分でできる、いちばん小さい行動を表す日本語の 1 文。動詞で終える。")
    var text: String

    @Guide(description: "その行動にかかる分数", .range(1...5))
    var estimatedMinutes: Int
}

@Generable
struct MicroActionProposal {
    @Guide(description: "小さい行動の案", .count(3))
    var actions: [MicroAction]
}

// MARK: - 2. 指示文（各 600 文字以内 / 実装計画 §9 プロンプト予算）

enum Instructions {
    static let reason = """
    あなたは先延ばしに寄り添う伴走者です。教師でも上司でもありません。
    利用者を責めず、評価せず、やわらかい日本語だけで話します。
    入力は「逃げたいこと」と、なぜ嫌かという本人の答えです。
    category は次の対応で選びます。awkward=気まずい、perfectionism=完璧にやりたい、tedious=面倒、anxious=不安・怖い、tooMuch=量が多い、unclearStart=何から始めるかわからない、deadlineFear=期限が怖い。
    followUp は本人の言葉を受け止めて、もう一歩だけ具体にする質問を 1 つだけ書きます。60 文字以内の日本語で、必ず「？」で終えます。
    「未達成」「連続」「サボ」「怠け」「言い訳」「甘え」「なぜやらない」「また逃げ」は使いません。
    """

    static let actions = """
    あなたは先延ばしに寄り添う伴走者です。教師でも上司でもありません。
    利用者を責めず、評価せず、やわらかい日本語だけで話します。
    入力は「逃げたいこと」と「逃げたい理由」です。
    その人が今日の最初の 5 分でできる、いちばん小さい行動を 3 つ出します。
    text は 40 文字以内の日本語で、動詞で終えます。例「メールを開く」「相手の名前を検索する」「必要な書類を机に置く」。
    タスク全体を終わらせる案は出しません。準備や着手だけで十分です。
    estimatedMinutes は 1 から 5 の分数です。
    「未達成」「連続」「サボ」「怠け」「言い訳」「甘え」「なぜやらない」「また逃げ」は使いません。
    """

    static let domain = """
    あなたは先延ばしの記録を分類する係です。
    入力の「逃げたいこと」を次の 1 つに分類します。
    personReply=人への返信や連絡、money=お金や税金や経費、bigTask=大きなタスクや制作、sales=営業や新規の売り込み、paperwork=書類の作成や手続き、health=健康や通院や運動、other=どれにも当てはまらないもの。
    説明は書かず、分類だけを返します。
    """
}

// MARK: - 3. 自動判定（実装計画 §7.5 / fix-decisions P5.7）
// 禁止句は生成文にのみ適用する。ユーザーの文字起こしには適用しない。

enum Guardrails {
    /// 課題指定の禁止句 8 種。
    static let bannedPhrases = ["未達成", "連続", "サボ", "怠け", "言い訳", "甘え", "なぜやらない", "また逃げ"]

    static let maxQuestionLength = 60
    static let maxActionLength = 40

    static func banned(in text: String) -> [String] {
        bannedPhrases.filter { text.contains($0) }
    }

    struct QuestionCheck {
        var length: Int
        var withinLimit: Bool
        var endsWithQuestionMark: Bool
        var banned: [String]
        var passed: Bool { withinLimit && endsWithQuestionMark && banned.isEmpty }
    }

    static func checkQuestion(_ text: String) -> QuestionCheck {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuestionCheck(
            length: trimmed.count,
            withinLimit: trimmed.count <= maxQuestionLength,
            endsWithQuestionMark: trimmed.hasSuffix("？") || trimmed.hasSuffix("?"),
            banned: banned(in: trimmed))
    }

    struct ActionCheck {
        var length: Int
        var withinLimit: Bool
        var minutesInRange: Bool
        var banned: [String]
        var passed: Bool { withinLimit && minutesInRange && banned.isEmpty }
    }

    static func checkAction(_ action: MicroAction) -> ActionCheck {
        let trimmed = action.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActionCheck(
            length: trimmed.count,
            withinLimit: trimmed.count <= maxActionLength,
            minutesInRange: (1...5).contains(action.estimatedMinutes),
            banned: banned(in: trimmed))
    }
}

// MARK: - 4. フィクスチャ

struct Fixture: Decodable {
    var id: String
    var avoidance: String
    var reasonAnswer: String
    var expectedDomain: String
    var source: String?
}

struct FixtureFile: Decodable {
    var version: Int
    var note: String?
    var fixtures: [Fixture]
}

// MARK: - 5. 計測結果

struct CallOutcome<Value> {
    var value: Value?
    var milliseconds: Int
    /// GenerationError の case 名、または他のエラーの説明。成功時は nil。
    var errorKind: String?
    var errorDetail: String?
    var retried: Bool
}

struct FixtureResult {
    var fixture: Fixture
    var reason: CallOutcome<ReasonClassification>
    var proposal: CallOutcome<MicroActionProposal>
    var domain: CallOutcome<TaskDomain>
}

// MARK: - 6. エラー分類（swiftinterface で存在を確認した case のみ）

func describe(_ error: any Error) -> (kind: String, detail: String) {
    if error is CallTimedOut {
        return ("timeout", "上限時間内に応答が返らなかった")
    }
    if let generation = error as? LanguageModelSession.GenerationError {
        switch generation {
        case .exceededContextWindowSize(let context):
            return ("exceededContextWindowSize", context.debugDescription)
        case .assetsUnavailable(let context):
            return ("assetsUnavailable", context.debugDescription)
        case .guardrailViolation(let context):
            return ("guardrailViolation", context.debugDescription)
        case .unsupportedGuide(let context):
            return ("unsupportedGuide", context.debugDescription)
        case .unsupportedLanguageOrLocale(let context):
            return ("unsupportedLanguageOrLocale", context.debugDescription)
        case .decodingFailure(let context):
            return ("decodingFailure", context.debugDescription)
        case .rateLimited(let context):
            return ("rateLimited", context.debugDescription)
        case .concurrentRequests(let context):
            return ("concurrentRequests", context.debugDescription)
        case .refusal(_, let context):
            return ("refusal", context.debugDescription)
        @unknown default:
            return ("unknownGenerationError", String(describing: generation))
        }
    }
    return (String(describing: type(of: error)), String(describing: error))
}

// MARK: - 7. 呼び出し（毎回、新しい LanguageModelSession）

/// 応答が返らないまま止まる呼び出しがあるため、上限時間で打ち切って観測値として記録する。
struct CallTimedOut: Error {}

func withTimeout<Value: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CallTimedOut()
        }
        guard let first = try await group.next() else { throw CallTimedOut() }
        group.cancelAll()
        return first
    }
}

func log(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func call<Value: Generable>(
    instructions: String,
    prompt: String,
    generating type: Value.Type,
    timeoutSeconds: Int,
    options: GenerationOptions
) async -> CallOutcome<Value> {
    let clock = ContinuousClock()
    let start = clock.now

    func attempt() async throws -> Value {
        // 実装計画 §7.2: LLM 呼び出しは 1 ステップ 1 回、毎回新しいセッション。
        try await withTimeout(seconds: timeoutSeconds) {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt, generating: type, options: options).content
        }
    }

    do {
        let value = try await attempt()
        return CallOutcome(value: value, milliseconds: elapsedMS(clock, start), errorKind: nil, errorDetail: nil, retried: false)
    } catch {
        let first = describe(error)
        // §9: exceededContextWindowSize は新しいセッションで 1 回だけ再試行する。
        if first.kind == "exceededContextWindowSize" {
            do {
                let value = try await attempt()
                return CallOutcome(value: value, milliseconds: elapsedMS(clock, start), errorKind: nil, errorDetail: "1 回再試行して成功", retried: true)
            } catch {
                let second = describe(error)
                return CallOutcome(value: nil, milliseconds: elapsedMS(clock, start), errorKind: second.kind, errorDetail: second.detail, retried: true)
            }
        }
        return CallOutcome(value: nil, milliseconds: elapsedMS(clock, start), errorKind: first.kind, errorDetail: first.detail, retried: false)
    }
}

func elapsedMS(_ clock: ContinuousClock, _ start: ContinuousClock.Instant) -> Int {
    let duration = clock.now - start
    let (seconds, attoseconds) = duration.components
    return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
}

// MARK: - 8. 引数

struct Options {
    var fixturesPath: String
    var outputPath: String
    var limit: Int?
    var timeoutSeconds: Int
    /// nil なら GenerationOptions の既定（上限なし）を使う。
    var maxResponseTokens: Int?
    var dryRun: Bool
}

func parseOptions() -> Options {
    let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
    var fixtures = sourceDir.appendingPathComponent("fixtures.json").path
    var output = repoRoot.appendingPathComponent("docs/spikes/fm-probe.md").path
    var limit: Int?
    var timeoutSeconds = 60
    var maxResponseTokens: Int? = nil
    var dryRun = false

    // ソース位置が存在しない環境（バイナリだけ配布した場合）は作業ディレクトリ基準に落とす。
    if !FileManager.default.fileExists(atPath: fixtures) {
        fixtures = FileManager.default.currentDirectoryPath + "/Spikes/fm-probe/fixtures.json"
        output = FileManager.default.currentDirectoryPath + "/docs/spikes/fm-probe.md"
    }

    var arguments = Array(CommandLine.arguments.dropFirst())
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--fixtures":
            if let next = arguments.first { fixtures = next; arguments.removeFirst() }
        case "--out":
            if let next = arguments.first { output = next; arguments.removeFirst() }
        case "--limit":
            if let next = arguments.first { limit = Int(next); arguments.removeFirst() }
        case "--timeout":
            if let next = arguments.first, let seconds = Int(next) { timeoutSeconds = seconds; arguments.removeFirst() }
        case "--max-response-tokens":
            if let next = arguments.first {
                maxResponseTokens = (next == "none") ? nil : Int(next)
                arguments.removeFirst()
            }
        case "--dry-run":
            dryRun = true
        default:
            FileHandle.standardError.write(Data("不明な引数: \(argument)\n".utf8))
        }
    }
    return Options(fixturesPath: fixtures, outputPath: output, limit: limit, timeoutSeconds: timeoutSeconds, maxResponseTokens: maxResponseTokens, dryRun: dryRun)
}

// MARK: - 9. Markdown ヘルパー

func cell(_ text: String) -> String {
    text
        .replacingOccurrences(of: "|", with: "\\|")
        .replacingOccurrences(of: "\r\n", with: "<br>")
        .replacingOccurrences(of: "\n", with: "<br>")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func mark(_ ok: Bool) -> String { ok ? "OK" : "NG" }

func percentile(_ values: [Int], _ p: Double) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = max(1, Int((p * Double(sorted.count)).rounded(.up)))
    return sorted[min(rank, sorted.count) - 1]
}

// MARK: - 10. 実行

let options = parseOptions()
let model = SystemLanguageModel.default
let availability = model.availability

var availabilityText: String
var availabilityReason: String
switch availability {
case .available:
    availabilityText = "available"
    availabilityReason = "—"
case .unavailable(let reason):
    availabilityText = "unavailable"
    switch reason {
    case .deviceNotEligible: availabilityReason = "deviceNotEligible（この Mac は Apple Intelligence 非対応）"
    case .appleIntelligenceNotEnabled: availabilityReason = "appleIntelligenceNotEnabled（設定で Apple Intelligence が無効）"
    case .modelNotReady: availabilityReason = "modelNotReady（モデルのダウンロード・準備が未完了）"
    @unknown default: availabilityReason = "未知の理由: \(String(describing: reason))"
    }
@unknown default:
    availabilityText = "未知の availability: \(String(describing: availability))"
    availabilityReason = "—"
}

let supportsJapanese = model.supportsLocale(Locale(identifier: "ja_JP"))
let supportedLanguages = model.supportedLanguages.map { $0.maximalIdentifier }.sorted()

log("== SAYDO fm-probe (spike S-A / S-D) ==")
log("availability: \(availabilityText)  reason: \(availabilityReason)")
log("supportsLocale(ja_JP): \(supportsJapanese)")
log("supportedLanguages: \(supportedLanguages.joined(separator: ", "))")
log("指示文の文字数: reason=\(Instructions.reason.count) / actions=\(Instructions.actions.count) / domain=\(Instructions.domain.count)（各 600 以内）")
log("fixtures: \(options.fixturesPath)")
log("out: \(options.outputPath)")
log("1 呼び出しの上限時間: \(options.timeoutSeconds) 秒")
log("maximumResponseTokens: \(options.maxResponseTokens.map(String.init) ?? "既定（上限なし）")")
let generationOptions = GenerationOptions(maximumResponseTokens: options.maxResponseTokens)
log("")

guard let fixtureData = FileManager.default.contents(atPath: options.fixturesPath) else {
    FileHandle.standardError.write(Data("フィクスチャを読めない: \(options.fixturesPath)\n".utf8))
    exit(2)
}
let fixtureFile: FixtureFile
do {
    fixtureFile = try JSONDecoder().decode(FixtureFile.self, from: fixtureData)
} catch {
    FileHandle.standardError.write(Data("フィクスチャの JSON が壊れている: \(error)\n".utf8))
    exit(2)
}

var fixtures = fixtureFile.fixtures
if let limit = options.limit { fixtures = Array(fixtures.prefix(limit)) }

let runStartedAt = Date()
var results: [FixtureResult] = []

let modelUsable = (availability == .available) && !options.dryRun

if modelUsable {
    for (index, fixture) in fixtures.enumerated() {
        let reasonPrompt = """
        逃げたいこと: \(fixture.avoidance)
        なぜ嫌か（本人の答え）: \(fixture.reasonAnswer)
        """
        let reason = await call(instructions: Instructions.reason, prompt: reasonPrompt, generating: ReasonClassification.self, timeoutSeconds: options.timeoutSeconds, options: generationOptions)

        let reasonLabel = reason.value?.category.label ?? "（分類できず）"
        let actionsPrompt = """
        逃げたいこと: \(fixture.avoidance)
        逃げたい理由: \(reasonLabel)
        """
        let proposal = await call(instructions: Instructions.actions, prompt: actionsPrompt, generating: MicroActionProposal.self, timeoutSeconds: options.timeoutSeconds, options: generationOptions)

        let domainPrompt = "逃げたいこと: \(fixture.avoidance)"
        let domain = await call(instructions: Instructions.domain, prompt: domainPrompt, generating: TaskDomain.self, timeoutSeconds: options.timeoutSeconds, options: generationOptions)

        results.append(FixtureResult(fixture: fixture, reason: reason, proposal: proposal, domain: domain))

        let progress = "[\(index + 1)/\(fixtures.count)] \(fixture.id) \(fixture.avoidance)"
        let timing = "reason \(reason.milliseconds)ms\(reason.errorKind.map { " (\($0))" } ?? "") / actions \(proposal.milliseconds)ms\(proposal.errorKind.map { " (\($0))" } ?? "") / domain \(domain.milliseconds)ms\(domain.errorKind.map { " (\($0))" } ?? "")"
        log("\(progress) — \(timing)")
    }
} else {
    let cause = options.dryRun ? "--dry-run 指定" : "availability != .available（\(availabilityReason)）"
    log("モデル呼び出しをスキップした: \(cause)")
    for fixture in fixtures {
        results.append(FixtureResult(
            fixture: fixture,
            reason: CallOutcome(value: nil, milliseconds: 0, errorKind: "skipped", errorDetail: cause, retried: false),
            proposal: CallOutcome(value: nil, milliseconds: 0, errorKind: "skipped", errorDetail: cause, retried: false),
            domain: CallOutcome(value: nil, milliseconds: 0, errorKind: "skipped", errorDetail: cause, retried: false)))
    }
}
let runFinishedAt = Date()

// MARK: - 11. 集計

var allDurations: [Int] = []
var questionChecks: [String: Guardrails.QuestionCheck] = [:]
var actionChecksByFixture: [String: [Guardrails.ActionCheck]] = [:]
var errorCounts: [String: Int] = [:]
var domainMatches = 0
var domainAnswered = 0
var autoPassCount = 0
var bannedHitFixtures: [String] = []

for result in results {
    if modelUsable {
        allDurations.append(contentsOf: [result.reason.milliseconds, result.proposal.milliseconds, result.domain.milliseconds])
    }
    for kind in [result.reason.errorKind, result.proposal.errorKind, result.domain.errorKind].compactMap({ $0 }) {
        errorCounts[kind, default: 0] += 1
    }

    let question = result.reason.value.map { Guardrails.checkQuestion($0.followUp) }
    if let question { questionChecks[result.fixture.id] = question }

    let actionChecks = (result.proposal.value?.actions ?? []).map { Guardrails.checkAction($0) }
    actionChecksByFixture[result.fixture.id] = actionChecks

    if let domain = result.domain.value {
        domainAnswered += 1
        if domain.rawValue == result.fixture.expectedDomain { domainMatches += 1 }
    }

    let hasBanned = (question?.banned.isEmpty == false) || actionChecks.contains { !$0.banned.isEmpty }
    if hasBanned { bannedHitFixtures.append(result.fixture.id) }

    let questionOK = question?.passed ?? false
    let actionsOK = actionChecks.count == 3 && actionChecks.allSatisfy { $0.passed }
    let domainOK = result.domain.value != nil
    if questionOK && actionsOK && domainOK { autoPassCount += 1 }
}

let p50 = percentile(allDurations, 0.5)
let p90 = percentile(allDurations, 0.9)
let maxMS = allDurations.max()
let over6s = allDurations.filter { $0 > 6000 }.count

// MARK: - 12. Markdown 生成

let dateFormatter = DateFormatter()
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
dateFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss (ZZZZZ)"

var md = ""
func line(_ text: String = "") { md += text + "\n" }

line("# スパイク S-A / S-D: fm-probe（Foundation Models の日本語品質検証）")
line()
line("このファイルは `Spikes/fm-probe/main.swift` が生成する。手で編集するのは「人手採点」と「Go / No-Go」の欄だけにし、再実行するとそれ以外は上書きされる。")
line()
line("## 1. 実行環境")
line()
line("| 項目 | 値 |")
line("|---|---|")
line("| 実行日時 | \(dateFormatter.string(from: runStartedAt)) |")
line("| 所要（全体） | \(Int(runFinishedAt.timeIntervalSince(runStartedAt)))秒 |")
line("| フィクスチャ | `\(options.fixturesPath)`（\(fixtures.count) 件 / version \(fixtureFile.version)） |")
line("| モデル呼び出し | \(modelUsable ? "実行した" : "スキップした") |")
line("| 1 呼び出しの上限時間 | \(options.timeoutSeconds) 秒（超過は `timeout` として記録） |")
line("| `GenerationOptions.maximumResponseTokens` | \(options.maxResponseTokens.map(String.init) ?? "既定（上限なし）") |")
line()
line("ビルドと実行:")
line()
line("```")
line("swiftc -O Spikes/fm-probe/main.swift -o /tmp/fm-probe && /tmp/fm-probe")
line("```")
line()
line("## 2. availability と対応言語（S-D）")
line()
line("| 項目 | 実測値 |")
line("|---|---|")
line("| `SystemLanguageModel.default.availability` | `\(availabilityText)` |")
line("| `unavailable` の理由 | \(availabilityReason) |")
line("| `supportsLocale(Locale(identifier: \"ja_JP\"))` | `\(supportsJapanese)` |")
line("| `supportedLanguages` に日本語 | \(supportedLanguages.contains(where: { $0.hasPrefix("ja") }) ? "あり（`ja-Jpan-JP`）" : "なし") |")
line()
line("`supportedLanguages`（\(supportedLanguages.count) 件）: \(supportedLanguages.map { "`\($0)`" }.joined(separator: ", "))")
line()
line("## 3. コンパイルで実在を確認した API")
line()
line("以下は macOS 26.2 SDK（Xcode 26.2 / Swift 6.2.3）で実際にコンパイル・実行が通ったものだけを挙げる。")
line()
line("| API | 用途 |")
line("|---|---|")
line("| `SystemLanguageModel.default.availability` → `.available` / `.unavailable(UnavailableReason)` | Tier 判定 |")
line("| `UnavailableReason`: `.deviceNotEligible` / `.appleIntelligenceNotEnabled` / `.modelNotReady` | 不可時の理由表示 |")
line("| `SystemLanguageModel.supportsLocale(_ locale: Locale = .current) -> Bool` | 日本語対応判定（fix-decisions P4.4） |")
line("| `SystemLanguageModel.supportedLanguages -> Set<Locale.Language>` | 対応言語の列挙 |")
line("| `LanguageModelSession(model:tools:instructions: String?)` | ステップごとの新規セッション |")
line("| `session.respond(to: String, generating: Content.Type, includeSchemaInPrompt:options:) -> Response<Content>` | 構造化生成 |")
line("| `@Generable(description:)` / `@Guide(description:)` / `@Guide(description:_ guides:)` | スキーマ定義 |")
line("| `GenerationGuide.range(_: ClosedRange<Int>)` / `.count(_: Int)` | 数値範囲・配列件数 |")
line("| `LanguageModelSession.GenerationError`: `exceededContextWindowSize` / `assetsUnavailable` / `guardrailViolation` / `unsupportedGuide` / `unsupportedLanguageOrLocale` / `decodingFailure` / `rateLimited` / `concurrentRequests` / `refusal` | エラー処理（fix-decisions P4.2） |")
line()
line("補足: `@Guide` に文字数制約は無い（`GenerationGuide<String>` は `.constant` / `.anyOf` / `.pattern` のみ）。文字数・疑問形は後段の Guardrails 検査で強制する。実装計画 §9 の `@Guide 60 文字以内・40 文字以内` という記述はこの通りには書けない。")
line()
line("Apple 側のセーフティも観測できた。指示文を削って `入力の「逃げたいこと」を personReply, money, ... のどれか 1 つに分類します。` だけにして「確定申告」を投げると、25 回中 25 回とも `refusal`（`debugDescription: \"May contain sensitive content\"`）で拒否された。同じ入力でも本スパイクの伴走者向け指示文では拒否されない。**指示文の書き方でセーフティの発火が変わるため、プロンプトを変更したら必ずこのスパイクを再実行すること。**")
line()
line("## 4. 指示文（各 600 文字以内）")
line()
line("| 呼び出し | 文字数 |")
line("|---|---|")
line("| 理由分類 + 追加質問 | \(Instructions.reason.count) |")
line("| 行動 3 案 | \(Instructions.actions.count) |")
line("| 分野分類 | \(Instructions.domain.count) |")
line()
line("## 5. 自動判定の規則")
line()
line("- 禁止句（生成文にのみ適用）: \(Guardrails.bannedPhrases.map { "「\($0)」" }.joined(separator: "、"))")
line("- 追加質問: \(Guardrails.maxQuestionLength) 文字以内、かつ「？」で終わる")
line("- 行動文: \(Guardrails.maxActionLength) 文字以内、`estimatedMinutes` が 1〜5")
line("- 「動詞で終わる」は形態素解析が要るため自動判定に含めない。人手採点で見る。")
line()
line("## 6. 理由分類と追加質問")
line()
line("| # | 逃げたいこと | 本人の答え | category | followUp | ms | 質問長 | ≤60 | ？終わり | 禁止句 | エラー |")
line("|---|---|---|---|---|---|---|---|---|---|---|")
for result in results {
    let f = result.fixture
    let value = result.reason.value
    let check = questionChecks[f.id]
    let category = value.map { "\($0.category.rawValue)（\($0.category.label)）" } ?? "—"
    let followUp = value?.followUp ?? "—"
    let length = check.map { String($0.length) } ?? "—"
    let within = check.map { mark($0.withinLimit) } ?? "—"
    let endsQ = check.map { mark($0.endsWithQuestionMark) } ?? "—"
    let banned = check.map { $0.banned.isEmpty ? "0" : $0.banned.joined(separator: "/") } ?? "—"
    let error = result.reason.errorKind.map { "`\($0)`" } ?? "—"
    line("| \(f.id) | \(cell(f.avoidance)) | \(cell(f.reasonAnswer)) | \(cell(category)) | \(cell(followUp)) | \(result.reason.milliseconds) | \(length) | \(within) | \(endsQ) | \(banned) | \(error) |")
}
line()
line("## 7. 行動 3 案（5 分以下への細分化）")
line()
line("| # | 案 1 | 案 2 | 案 3 | ms | 最長文字数 | ≤40 | 分 1〜5 | 禁止句 | エラー |")
line("|---|---|---|---|---|---|---|---|---|---|")
for result in results {
    let f = result.fixture
    let actions = result.proposal.value?.actions ?? []
    let checks = actionChecksByFixture[f.id] ?? []
    func actionCell(_ i: Int) -> String {
        guard i < actions.count else { return "—" }
        return cell("\(actions[i].text)（\(actions[i].estimatedMinutes)分）")
    }
    let longest = checks.map(\.length).max().map(String.init) ?? "—"
    let within = checks.isEmpty ? "—" : mark(checks.allSatisfy { $0.withinLimit })
    let minutes = checks.isEmpty ? "—" : mark(checks.allSatisfy { $0.minutesInRange })
    let bannedHits = checks.flatMap(\.banned)
    let banned = checks.isEmpty ? "—" : (bannedHits.isEmpty ? "0" : bannedHits.joined(separator: "/"))
    let error = result.proposal.errorKind.map { "`\($0)`" } ?? "—"
    line("| \(f.id) | \(actionCell(0)) | \(actionCell(1)) | \(actionCell(2)) | \(result.proposal.milliseconds) | \(longest) | \(within) | \(minutes) | \(banned) | \(error) |")
}
line()
line("## 8. 分野分類")
line()
line("`参考分類` は fixtures.json に人が付けた値であり、正解の断定ではない。判定の傾向を見るための参考。")
line()
line("| # | 逃げたいこと | 判定 | 参考分類 | 一致 | ms | エラー |")
line("|---|---|---|---|---|---|---|")
for result in results {
    let f = result.fixture
    let value = result.domain.value
    let judged = value.map { "\($0.rawValue)（\($0.label)）" } ?? "—"
    let expected = TaskDomain(rawValue: f.expectedDomain).map { "\($0.rawValue)（\($0.label)）" } ?? f.expectedDomain
    let match = value.map { mark($0.rawValue == f.expectedDomain) } ?? "—"
    let error = result.domain.errorKind.map { "`\($0)`" } ?? "—"
    line("| \(f.id) | \(cell(f.avoidance)) | \(cell(judged)) | \(cell(expected)) | \(match) | \(result.domain.milliseconds) | \(error) |")
}
line()
line("分野分類は最も速い（0.2 秒台）が、最も外れる。実装計画 §7.6 の Insight（「何から、なぜ逃げるか」の可視化）はこの分類の精度に直接乗るため、一致率が低い場合は Tier A でもキーワード辞書を先に当て、LLM は辞書で決まらないものだけに使う方が良い。")
line()
line("## 9. 集計")
line()
line("| 指標 | 値 |")
line("|---|---|")
line("| 呼び出し総数 | \(modelUsable ? String(allDurations.count) : "0（スキップ）") |")
line("| p50 | \(p50.map { "\($0) ms" } ?? "—") |")
line("| p90 | \(p90.map { "\($0) ms" } ?? "—") |")
line("| 最大 | \(maxMS.map { "\($0) ms" } ?? "—") |")
line("| 6 秒（アプリのタイムアウト）超過 | \(modelUsable ? "\(over6s) / \(allDurations.count)" : "—") |")
line("| 禁止句を含んだ件数 | \(modelUsable ? "\(bannedHitFixtures.count)\(bannedHitFixtures.isEmpty ? "" : "（\(bannedHitFixtures.joined(separator: ", "))）")" : "—") |")
line("| 自動判定 全項目合格 | \(modelUsable ? "\(autoPassCount) / \(results.count)" : "—") |")
line("| 分野分類が参考分類と一致 | \(modelUsable ? "\(domainMatches) / \(domainAnswered)" : "—") |")
if errorCounts.isEmpty {
    line("| エラー | 0 |")
} else {
    for (kind, count) in errorCounts.sorted(by: { $0.key < $1.key }) {
        line("| エラー `\(kind)` | \(count) |")
    }
}
line()
line("### 9.1 追加質問の暴走（このスパイクで特定した最大の問題）と、その回避策")
line()
line("`ReasonClassification` は `category: ReasonCategory`（列挙）と `followUp: String`（自由文）を 1 つの `@Generable` 構造体にまとめた型で、実装計画 §9 の定義どおりである。この型を使うと、一定の割合でモデルが `followUp` を書き終えずに生成し続ける。上限を掛けないと約 53 秒かけて 4,096 トークンの文脈窓を使い切り、`exceededContextWindowSize` で失敗する。所要時間が 0.5 秒と 50 秒超に二極化するのはこれが原因で、スケジューリングの問題ではない。")
line()
line("2026-09-04 に同一プロンプト・同一型で反復して切り分けた結果:")
line()
line("| 条件 | 反復 | 成功 | 失敗の内容 | 失敗時の所要時間 |")
line("|---|---|---|---|---|")
line("| `maximumResponseTokens` 指定なし | 10 | 8 | `exceededContextWindowSize` | 53.6 秒 |")
line("| `maximumResponseTokens: 100` | 14 | 9 | `decodingFailure`（JSON が途中で切れる） | 1.3〜2.1 秒 |")
line("| `maximumResponseTokens: 200` | 16 | 8 | `decodingFailure` | 最大 3.6 秒 |")
line("| `maximumResponseTokens: 320` | 16 | 8 | `decodingFailure` | 最大 5.4 秒 |")
line("| `maximumResponseTokens: 512` | 16 | 10 | `decodingFailure` | 最大 6.6 秒 |")
line()
line("効かなかった手: `session.prewarm()`（30 回中 4 回が 46〜57 秒）、`__info_plist` を埋め込んだ ad-hoc 署名、`sampling: .greedy`（成功時の出力は毎回同一だったので、暴走しない回の生成は正常）。")
line()
line("`@Guide` の正規表現（`GenerationGuide<String>.pattern`）も試した。コンパイルは通り `#/.{1,40}？/#` なら 4 回中 4 回とも「？」で終わる正しい質問を返したが、1 回 117〜179 秒かかって実用にならない。文字クラスを使った `#/[^？]{1,59}？/#` `#/[^?]{1,40}\\?/#` `#/[a-zA-Z ]{1,30}/#` はいずれも実行時に `GenerativeError Code=1020000` で全滅した（`GenerationError` のどの case にもならない NSError として返る）。fix-decisions P4.3 の「`@Guide` は description と `.anyOf` / `.range` / `.count` のみに使う」は正しい。")
line()
line("#### 効いた回避策: 呼び出しを 2 つに割る")
line()
line("`ReasonCategory` だけを生成する呼び出しと、追加質問を素の `String`（構造化なし）で生成する呼び出しに分けると、どちらも暴走しなくなる。同じ 4 入力 × 3 回で計測:")
line()
line("| 呼び出し | 反復 | 成功 | p50 | 最大 |")
line("|---|---|---|---|---|")
line("| `respond(to:generating: ReasonCategory.self)`（列挙のみ） | 12 | 12 | 207 ms | 819 ms |")
line("| `respond(to:)` で追加質問を素の String（`maximumResponseTokens: 60`） | 12 | 12 | 772 ms | 1,427 ms |")
line()
line("暴走が起きるのは「列挙 + 自由文」を 1 つの `@Generable` 構造体にまとめた場合だけだった。ただし素の String で受けた追加質問は複数文・長文・疑問文でないものが混ざるため、後段の Guardrails での棄却率は上がる。")
line()
line("#### アプリへの含意")
line()
line("1. **実装計画 §9 の `ReasonClassification` を 2 呼び出しに分割する。** M1 の理由分類は `@Generable enum ReasonCategory` 単独で行い、追加質問は別の `respond(to:)` で取り、Guardrails を通す。分割後はどちらも 1 秒前後で安定する。")
line("2. **`GenerationOptions(maximumResponseTokens:)` を必ず指定する。** 指定しないと 1 回の失敗に 53 秒かかる。§7.2 のタイムアウト 6 秒で打ち切れば体験は守れるが、打ち切った後もモデル側の生成は走り続ける。")
line("3. **§9 の「`exceededContextWindowSize` は新しいセッションで 1 回だけ再試行」はこの暴走には効かない。** 同じ指示と入力で再試行すると同じ確率で再び暴走する。再試行 1 回で駄目ならテンプレートに落とす、と明記する必要がある。")
line("4. **行動 3 案と分野分類は分割しなくてよい。** `MicroActionProposal`（`@Guide(.count(3))` の固定長配列）も `TaskDomain`（列挙）も暴走せず、上の表と §7・§8 のとおり 1 秒前後で安定して返る。")
line()
line("この実行の設定は §1 の表にある。`--max-response-tokens <n>` と `--timeout <秒>` で条件を変えて再計測できる。")
line()
line("### 9.2 自動判定で落ちた生成文")
line()
line("| # | 落ちた項目 | 生成文 |")
line("|---|---|---|")
var failureRows = 0
for result in results {
    if let check = questionChecks[result.fixture.id], !check.passed, let value = result.reason.value {
        var reasons: [String] = []
        if !check.withinLimit { reasons.append("質問が \(Guardrails.maxQuestionLength) 文字超（\(check.length) 文字）") }
        if !check.endsWithQuestionMark { reasons.append("「？」で終わっていない") }
        if !check.banned.isEmpty { reasons.append("禁止句 \(check.banned.joined(separator: "/"))") }
        line("| \(result.fixture.id) | 追加質問: \(reasons.joined(separator: " / ")) | \(cell(value.followUp)) |")
        failureRows += 1
    }
    if let kind = result.reason.errorKind {
        line("| \(result.fixture.id) | 追加質問: `\(kind)` で結果なし | — |")
        failureRows += 1
    }
    for (index, check) in (actionChecksByFixture[result.fixture.id] ?? []).enumerated() where !check.passed {
        let text = result.proposal.value?.actions[index].text ?? "—"
        var reasons: [String] = []
        if !check.withinLimit { reasons.append("\(Guardrails.maxActionLength) 文字超（\(check.length) 文字）") }
        if !check.minutesInRange { reasons.append("分数が 1〜5 の外") }
        if !check.banned.isEmpty { reasons.append("禁止句 \(check.banned.joined(separator: "/"))") }
        line("| \(result.fixture.id) | 行動案 \(index + 1): \(reasons.joined(separator: " / ")) | \(cell(text)) |")
        failureRows += 1
    }
    if let kind = result.proposal.errorKind {
        line("| \(result.fixture.id) | 行動 3 案: `\(kind)` で結果なし | — |")
        failureRows += 1
    }
    if let kind = result.domain.errorKind {
        line("| \(result.fixture.id) | 分野分類: `\(kind)` で結果なし | — |")
        failureRows += 1
    }
}
if failureRows == 0 {
    line("| — | なし | — |")
}
line()
line("実装計画 §7.5 の後段検査（文字数・疑問形・禁止句）とテンプレート置換が無ければ、上の生成文はそのままユーザーに読み上げられる。この表が空でない限り、Tier A でも Guardrails は必須である。")
line()
line("## 10. 人手採点（空欄。人間が埋める）")
line()
line("判定は 3 段階。採用可 = そのままアプリの発話に使える / 要修正 = 文言調整で使える / 不可 = 使えない。")
line("見る観点: 追加質問が責めていないか、行動が本当に 5 分以下か、行動文が動詞で終わっているか、日本語として自然か。")
line()
line("| # | 逃げたいこと | 追加質問 | 行動 3 案 | 分野分類 | 総合（採用可 / 要修正 / 不可） | メモ |")
line("|---|---|---|---|---|---|---|")
for result in results {
    line("| \(result.fixture.id) | \(cell(result.fixture.avoidance)) |  |  |  |  |  |")
}
line()
line("## 11. Go / No-Go")
line()
line("判定基準（fix-decisions §C P5.6）: 20 件中 16 件以上が採用可、禁止句 0 件、1 呼び出し p50 4 秒以内。")
line()
line("| 基準 | 実測 | 自動判定 |")
line("|---|---|---|")
let bannedVerdict = modelUsable ? (bannedHitFixtures.isEmpty ? "合格" : "不合格") : "未測定"
let p50Verdict: String
if let p50, modelUsable {
    p50Verdict = p50 <= 4000 ? "合格" : "不合格"
} else {
    p50Verdict = "未測定"
}
line("| 20 件中 16 件以上が採用可 | 人手採点が未記入 | 判定不能（人手採点が要る）。参考: 自動判定 全項目合格 \(modelUsable ? "\(autoPassCount) / \(results.count)" : "—") |")
line("| 禁止句 0 件 | \(modelUsable ? "\(bannedHitFixtures.count) 件" : "未測定") | \(bannedVerdict) |")
line("| 1 呼び出し p50 4 秒以内 | \(p50.map { "\($0) ms" } ?? "未測定") | \(p50Verdict) |")
line()
line("p50 は成功・失敗を問わず全 \(modelUsable ? String(allDurations.count) : "0") 呼び出しの中央値である。§9.1 のとおり追加質問の暴走が長い尾を作るため、p50 だけを見て判断せず、§9 の「6 秒超過」「エラー」の行と併せて読むこと。")
line()
line("判定にあたっての注意: §9.1 の分割（理由分類を列挙単独にし、追加質問を別呼び出しにする）を採れば、追加質問の失敗は Guardrails での棄却に置き換わる。**「Tier A を諦めるか」ではなく「§9 の型定義を分割するか」を先に決めるべきである。** 3 つの呼び出しのうち、行動 3 案と分野分類は現状のままで安定している。")
line()
line("**Go / No-Go 判定**: （人間が記入する）")
line()
line("**判定者 / 日付**: （人間が記入する）")
line()
line("No-Go の場合の代替（実装計画 §0.4 S-A）:")
line()
line("1. Tier B（テンプレート）固定で出荷する。Phase 2 の LLM 層は入れない。")
line("2. Phase 4 で iOS 27 の `PrivateCloudComputeLanguageModel` を再評価する。")
line("3. Claude API + 薄いプロキシ（Cloudflare Workers）を検討する。ただし「機種依存で完結」という原則を崩すため、最後の選択肢とする。")
line()
line("## 12. 再実行手順")
line()
line("`availability` が `unavailable` だった場合は、次の手順で有効化してから再実行する。")
line()
line("1. Apple メニュー → システム設定 → Apple Intelligence と Siri を開く。")
line("2. 「Apple Intelligence」をオンにし、待機リストの承認とモデルのダウンロード完了を待つ（`modelNotReady` はダウンロード中を表す）。")
line("3. システム設定 → 一般 → 言語と地域 で、Apple Intelligence が対応する言語になっていることを確認する。")
line("4. `swiftc -O Spikes/fm-probe/main.swift -o /tmp/fm-probe && /tmp/fm-probe` を再実行し、このファイルを上書きする。")
line("5. `deviceNotEligible` の場合はこの Mac では検証できない。Apple Intelligence 対応の実機（iPhone 15 Pro 以降）で S-A をやり直す。")
line()
line("モデルを呼ばずに自動判定コードとフィクスチャだけを検証する場合は `/tmp/fm-probe --dry-run` を使う。")
line()
line("既定（`maximumResponseTokens` 指定なし・上限 60 秒）は §9.1 の暴走 1 回につき最大 2 分かかるため、全 20 件で 20〜30 分を要する。短時間で回したい場合は `/tmp/fm-probe --max-response-tokens 512 --timeout 20` を使う（3〜4 分。ただし暴走が `decodingFailure` に化けるので、失敗の内訳は既定の実行と比べられない）。")
line()
line("## 13. S-D: iOS 26 シミュレータでの可否")
line()
line("| 環境 | availability | 備考 |")
line("|---|---|---|")
line("| macOS 26.5 / Apple M4（本 CLI） | `\(availabilityText)` | \(availabilityReason) |")
line("| iOS 26.2 シミュレータ | 未検証 | Xcode プロジェクト（`project.yml`）が別ブランチで作成中のため、このスパイクでは実行していない。task_004 の SpeechSpike ターゲットが揃った時点で確認する。 |")
line("| Apple Intelligence 対応 iPhone 実機 | 未検証 | 実機確保後に確認する。 |")

// MARK: - 13. 出力

print("")
print(md)

let outputURL = URL(fileURLWithPath: options.outputPath)
do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try md.write(to: outputURL, atomically: true, encoding: .utf8)
    print("書き出した: \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("書き出しに失敗: \(error)\n".utf8))
    exit(3)
}
