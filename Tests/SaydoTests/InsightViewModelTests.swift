import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// `InsightViewModel` の状態遷移（task_016 / retention R9）。
///
/// インメモリの `ModelContainer` に固定データを入れ、`Repository` 経由で読み出した結果が
/// 「3 件未満 → 何も出さない」「3 件目 → 1 行」「7 日 → 週次」になることを確かめる。
@MainActor
final class InsightViewModelTests: XCTestCase {

    private var root: URL!
    private var store: AudioFileStore!
    private var repository: Repository!

    /// 端末の暦・時間帯に依らないよう、テストは西暦 + Asia/Tokyo で固定する。
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private var today: Date!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoInsightViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = AudioFileStore(rootDirectory: root)
        repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
        await repository.configure(audioFileStore: store)
        today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))
        )
    }

    override func tearDown() async throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        repository = nil
        store = nil
        root = nil
        today = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func day(_ offset: Int) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
    }

    /// 1 日 1 件の宣言を積む。
    ///
    /// `AvoidanceItem` は同じ題目を使い回して分野を上書きするので、分野ごとに題目を分ける。
    private func record(
        daysAgo offset: Int,
        domain: TaskDomain,
        reason: ReasonCategory?
    ) async throws {
        let createdAt = try day(offset)
        let draft = CommitmentDraft(
            avoidanceTitle: "avoid-\(domain.rawValue)",
            domain: domain,
            reason: reason,
            microAction: MicroAction(text: "open the file", estimatedMinutes: 5),
            createdAt: createdAt
        )
        _ = try await repository.createCommitment(draft, calendar: calendar)
    }

    private func makeViewModel(
        reflectionProvider: (@Sendable (WeeklyStats) async throws -> String)? = nil
    ) -> InsightViewModel {
        InsightViewModel(
            repository: repository,
            calendar: calendar,
            now: { [today] in today ?? .now },
            reflectionProvider: reflectionProvider
        )
    }

    /// 7 日ぶんの固定データ。
    ///
    /// 分野: 人への返信 2 / お金 1 / 大きなタスク 1 / 営業 1 / 書類 1 / 健康 1 = 7 件（6 分野）。
    /// 理由: 気まずい 2 / 完璧にやりたい 1 / 面倒 1、残り 3 件は理由なし
    /// （母数は理由が付いた 4 件なので 50% / 25% / 25%）。
    private func seedSevenDays() async throws {
        try await record(daysAgo: 0, domain: .reply, reason: .awkward)
        try await record(daysAgo: 1, domain: .reply, reason: .awkward)
        try await record(daysAgo: 2, domain: .money, reason: .perfectionism)
        try await record(daysAgo: 3, domain: .bigTask, reason: .tedious)
        try await record(daysAgo: 4, domain: .sales, reason: nil)
        try await record(daysAgo: 5, domain: .paperwork, reason: nil)
        try await record(daysAgo: 6, domain: .health, reason: nil)
    }

    // MARK: 3 件未満

    func testNoRecordsShowNothing() async throws {
        let model = makeViewModel()

        await model.load()

        XCTAssertEqual(model.state, .insufficient)
        XCTAssertNil(model.cardLine)
    }

    func testTwoRecordsShowNothing() async throws {
        try await record(daysAgo: 0, domain: .reply, reason: .awkward)
        try await record(daysAgo: 1, domain: .reply, reason: .awkward)
        let model = makeViewModel()

        await model.load()

        let recordedCount = try await repository.recordedCommitmentCount()
        XCTAssertEqual(recordedCount, 2)
        XCTAssertEqual(model.state, .insufficient)
        XCTAssertNil(model.cardLine)
    }

    // MARK: 3 件目（retention R9）

    func testThirdRecordProducesTheOneLineInsight() async throws {
        try await record(daysAgo: 0, domain: .reply, reason: .awkward)
        try await record(daysAgo: 1, domain: .reply, reason: .awkward)
        try await record(daysAgo: 2, domain: .money, reason: .perfectionism)
        let model = makeViewModel()

        await model.load()

        let expected = InsightCopy.firstInsight(total: 3, count: 2, domain: .reply)
        XCTAssertEqual(model.state, .firstInsight(line: expected))
        XCTAssertEqual(model.cardLine, expected)
    }

    /// 偏りが無い（最多が 1 件）ときは 1 行を出さない。
    func testThreeRecordsWithoutABiasShowNothing() async throws {
        try await record(daysAgo: 0, domain: .reply, reason: .awkward)
        try await record(daysAgo: 1, domain: .money, reason: .awkward)
        try await record(daysAgo: 2, domain: .health, reason: .awkward)
        let model = makeViewModel()

        await model.load()

        XCTAssertEqual(model.state, .insufficient)
    }

    // MARK: 7 日そろったとき

    func testSevenDaysProduceTheWeeklyInsight() async throws {
        try await seedSevenDays()
        let model = makeViewModel()

        await model.load()

        guard case .weekly(let insight) = model.state else {
            return XCTFail("週次にならなかった: \(model.state)")
        }

        // 上位 5。件数の同数は rawValue の昇順（`WeeklyStats.topDomains`）。営業は 6 番目で落ちる。
        XCTAssertEqual(insight.topDomains, [.reply, .bigTask, .health, .money, .paperwork])

        // 理由の母数は理由が付いた 4 件（実装計画 §7.6）。
        XCTAssertEqual(insight.reasons.map(\.reason), [.awkward, .perfectionism, .tedious])
        XCTAssertEqual(insight.reasons[0].ratio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(insight.reasons[1].ratio, 0.25, accuracy: 0.0001)
        XCTAssertEqual(insight.reasons[2].ratio, 0.25, accuracy: 0.0001)

        XCTAssertEqual(insight.reflection, InsightCopy.reflection(reason: .awkward, domain: .reply))
        let firstDay = try day(6)
        XCTAssertEqual(insight.firstDay, calendar.startOfDay(for: firstDay))
        XCTAssertEqual(insight.lastDay, calendar.startOfDay(for: today))
        XCTAssertEqual(model.cardLine, insight.reflection)
    }

    // MARK: 振り返り 1 文の差し込み口（task_015）

    func testReflectionProviderReplacesTheTemplate() async throws {
        try await seedSevenDays()
        let generated = "今週は人に返す言葉を考える場面から離れていた日が多かったみたいです。"
        let model = makeViewModel(reflectionProvider: { _ in generated })

        await model.load()

        guard case .weekly(let insight) = model.state else {
            return XCTFail("週次にならなかった: \(model.state)")
        }
        XCTAssertEqual(insight.reflection, generated)
    }

    func testReflectionProviderFailureFallsBackToTheTemplate() async throws {
        struct ProviderFailure: Error {}
        try await seedSevenDays()
        let model = makeViewModel(reflectionProvider: { _ in throw ProviderFailure() })

        await model.load()

        guard case .weekly(let insight) = model.state else {
            return XCTFail("週次にならなかった: \(model.state)")
        }
        XCTAssertEqual(insight.reflection, InsightCopy.reflection(reason: .awkward, domain: .reply))
    }

    /// Guardrails を通らない文はテンプレートに落ちる（実装計画 §7.5）。
    func testReflectionProviderViolationFallsBackToTheTemplate() async throws {
        try await seedSevenDays()
        let model = makeViewModel(reflectionProvider: { _ in "今週は未達成です。" })

        await model.load()

        guard case .weekly(let insight) = model.state else {
            return XCTFail("週次にならなかった: \(model.state)")
        }
        XCTAssertEqual(insight.reflection, InsightCopy.reflection(reason: .awkward, domain: .reply))
    }
}
