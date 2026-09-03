import Foundation
import XCTest

@testable import SaydoCore

/// `InsightCalculator` のテスト。
///
/// 企画メモ §11 の例（気まずさ 38% / 完璧主義 27% / 面倒 21% / 不安 14%、
/// 逃げやすいこと上位 5）を再現するフィクスチャを持つ。
final class InsightCalculatorTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        guard let date = calendar.date(from: components) else {
            fatalError("invalid date components")
        }
        return date
    }

    private func expand<Value>(_ plan: [(Value, Int)]) -> [Value] {
        plan.flatMap { value, count in Array(repeating: value, count: count) }
    }

    /// 企画メモ §11 のフィクスチャ。
    ///
    /// 分野: 人への返信 18 / お金 14 / 大きなタスク 11 / 営業 8 / 書類 5 = 56 件。
    /// 理由: 気まずさ 21 / 完璧主義 15 / 面倒 12 / 不安 8 = 56 件
    /// （21/56 = 37.5% → 38、15/56 = 26.8% → 27、12/56 = 21.4% → 21、8/56 = 14.3% → 14）。
    private func conceptMemoFixture(weekStart: Date) -> [InsightInput] {
        let domains: [TaskDomain] = expand([
            (.reply, 18),
            (.money, 14),
            (.bigTask, 11),
            (.sales, 8),
            (.paperwork, 5)
        ])
        let reasons: [ReasonCategory] = expand([
            (.awkward, 21),
            (.perfectionism, 15),
            (.tedious, 12),
            (.anxious, 8)
        ])
        XCTAssertEqual(domains.count, reasons.count)

        return zip(domains, reasons).enumerated().map { index, pair in
            InsightInput(
                date: calendar.date(byAdding: .day, value: index % 7, to: weekStart) ?? weekStart,
                domain: pair.0,
                reason: pair.1,
                outcome: .pending
            )
        }
    }

    private func percentages(_ stats: WeeklyStats) -> [ReasonCategory: Int] {
        stats.reasonRatios.mapValues { Int(($0 * 100).rounded()) }
    }

    // MARK: - 企画メモ §11 の再現

    func testReasonPercentagesMatchConceptMemoExample() {
        let weekStart = day(2026, 8, 31)
        let stats = InsightCalculator.weeklyStats(
            from: conceptMemoFixture(weekStart: weekStart),
            weekStart: weekStart
        )

        XCTAssertEqual(percentages(stats)[.awkward], 38)
        XCTAssertEqual(percentages(stats)[.perfectionism], 27)
        XCTAssertEqual(percentages(stats)[.tedious], 21)
        XCTAssertEqual(percentages(stats)[.anxious], 14)
        XCTAssertEqual(stats.reasonRatios.count, 4)
    }

    func testTopDomainsMatchConceptMemoExample() {
        let weekStart = day(2026, 8, 31)
        let stats = InsightCalculator.weeklyStats(
            from: conceptMemoFixture(weekStart: weekStart),
            weekStart: weekStart
        )

        XCTAssertEqual(stats.totalCount, 56)
        XCTAssertEqual(
            stats.domainCounts,
            [.reply: 18, .money: 14, .bigTask: 11, .sales: 8, .paperwork: 5]
        )
        XCTAssertEqual(stats.topDomains(limit: 5), [.reply, .money, .bigTask, .sales, .paperwork])
        XCTAssertEqual(stats.weekStart, weekStart)
    }

    // MARK: - 母数

    func testReasonRatiosUseOnlyEntriesWithReason() {
        let weekStart = day(2026, 8, 31)
        var inputs = conceptMemoFixture(weekStart: weekStart)
        // 理由が未確定の 10 件を足しても割合は変わらない（reason != nil が母数）。
        for index in 0..<10 {
            inputs.append(
                InsightInput(
                    date: calendar.date(byAdding: .day, value: index % 7, to: weekStart) ?? weekStart,
                    domain: .other,
                    reason: nil,
                    outcome: .notYet
                )
            )
        }

        let stats = InsightCalculator.weeklyStats(from: inputs, weekStart: weekStart)
        XCTAssertEqual(percentages(stats)[.awkward], 38)
        XCTAssertEqual(percentages(stats)[.perfectionism], 27)
        XCTAssertEqual(percentages(stats)[.tedious], 21)
        XCTAssertEqual(percentages(stats)[.anxious], 14)
        // 分野は増える。
        XCTAssertEqual(stats.domainCounts[.other], 10)
        XCTAssertEqual(stats.totalCount, 66)
    }

    func testEntriesWithoutDomainAreNotCounted() {
        let weekStart = day(2026, 8, 31)
        let inputs = [
            InsightInput(date: weekStart, domain: nil, reason: .tedious),
            InsightInput(date: weekStart, domain: .money, reason: .tedious)
        ]
        let stats = InsightCalculator.weeklyStats(from: inputs, weekStart: weekStart)

        XCTAssertEqual(stats.totalCount, 1)
        XCTAssertEqual(stats.domainCounts, [.money: 1])
        XCTAssertEqual(stats.reasonRatios[.tedious], 1.0)
    }

    func testEmptyInputProducesEmptyStats() {
        let weekStart = day(2026, 8, 31)
        let stats = InsightCalculator.weeklyStats(from: [], weekStart: weekStart)

        XCTAssertEqual(stats.totalCount, 0)
        XCTAssertTrue(stats.domainCounts.isEmpty)
        XCTAssertTrue(stats.reasonRatios.isEmpty)
        XCTAssertTrue(stats.topDomains().isEmpty)
        XCTAssertTrue(stats.topReasons().isEmpty)
    }

    // MARK: - 週の切り出し

    func testWeekContainingFiltersOutOtherWeeks() {
        let inside = day(2026, 9, 2)
        let outside = day(2026, 9, 20)
        let inputs = [
            InsightInput(date: inside, domain: .reply, reason: .awkward),
            InsightInput(date: outside, domain: .money, reason: .tedious)
        ]

        let stats = InsightCalculator.weeklyStats(from: inputs, weekContaining: inside, calendar: calendar)
        XCTAssertEqual(stats.domainCounts, [.reply: 1])
        XCTAssertEqual(stats.reasonRatios[.awkward], 1.0)
        XCTAssertNil(stats.reasonRatios[.tedious])
    }

    // MARK: - 3 件目のインサイト（retention-strategy R9）

    func testFirstInsightAppearsOnThirdEntry() {
        let base = day(2026, 9, 1)
        let inputs = [
            InsightInput(date: base, domain: .reply, reason: .awkward),
            InsightInput(date: base, domain: .money, reason: .tedious),
            InsightInput(date: base, domain: .reply, reason: .awkward)
        ]

        XCTAssertEqual(InsightCalculator.firstInsight(from: inputs), "3 回のうち 2 回が『人への返信』")
    }

    func testFirstInsightIsNilBeforeThirdEntry() {
        let base = day(2026, 9, 1)
        let inputs = [
            InsightInput(date: base, domain: .reply, reason: .awkward),
            InsightInput(date: base, domain: .reply, reason: .awkward)
        ]

        XCTAssertNil(InsightCalculator.firstInsight(from: inputs))
        XCTAssertEqual(InsightCalculator.firstInsightThreshold, 3)
    }

    func testFirstInsightIsNilWhenThereIsNoRepeatedDomain() {
        let base = day(2026, 9, 1)
        let inputs = [
            InsightInput(date: base, domain: .reply),
            InsightInput(date: base, domain: .money),
            InsightInput(date: base, domain: .health)
        ]

        XCTAssertNil(InsightCalculator.firstInsight(from: inputs))
    }

    func testFirstInsightIgnoresEntriesWithoutDomain() {
        let base = day(2026, 9, 1)
        let inputs = [
            InsightInput(date: base, domain: .reply),
            InsightInput(date: base, domain: nil),
            InsightInput(date: base, domain: .reply)
        ]

        XCTAssertNil(InsightCalculator.firstInsight(from: inputs))
    }

    // MARK: - 週次の振り返り 1 文

    func testWeeklyReflectionUsesTopReasonAndTopDomain() {
        let weekStart = day(2026, 8, 31)
        let stats = InsightCalculator.weeklyStats(
            from: conceptMemoFixture(weekStart: weekStart),
            weekStart: weekStart
        )

        XCTAssertEqual(
            InsightCalculator.weeklyReflection(for: stats),
            InsightCopy.reflection(reason: .awkward, domain: .reply)
        )
    }

    func testWeeklyReflectionFallsBackToDomainOnlyWhenNoReasonRecorded() {
        let weekStart = day(2026, 8, 31)
        let inputs = (0..<3).map { index in
            InsightInput(
                date: calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart,
                domain: .paperwork,
                reason: nil
            )
        }
        let stats = InsightCalculator.weeklyStats(from: inputs, weekStart: weekStart)

        XCTAssertEqual(
            InsightCalculator.weeklyReflection(for: stats),
            InsightCopy.reflection(domain: .paperwork)
        )
    }

    func testWeeklyReflectionSaysNotEnoughDataBelowThreshold() {
        let weekStart = day(2026, 8, 31)
        let inputs = [
            InsightInput(date: weekStart, domain: .reply, reason: .awkward),
            InsightInput(date: weekStart, domain: .reply, reason: .awkward)
        ]
        let stats = InsightCalculator.weeklyStats(from: inputs, weekStart: weekStart)

        XCTAssertEqual(InsightCalculator.weeklyReflection(for: stats), InsightCopy.notEnoughData)
    }

    func testEveryReasonAndDomainCombinationHasATemplate() {
        for reason in ReasonCategory.allCases {
            for domain in TaskDomain.allCases {
                let sentence = InsightCopy.reflection(reason: reason, domain: domain)
                XCTAssertFalse(sentence.isEmpty)
                XCTAssertTrue(
                    sentence.contains(domain.displayName),
                    "分野名が入っていない: \(reason.rawValue) × \(domain.rawValue)"
                )
            }
        }
        XCTAssertEqual(
            InsightCopy.allTexts.count,
            1 + TaskDomain.allCases.count * (1 + ReasonCategory.allCases.count + 1)
        )
    }

    // MARK: - 責めない

    func testNoInsightTextContainsForbiddenPhrase() {
        for text in InsightCopy.allTexts {
            for phrase in NotificationCopyTests.forbiddenPhrases {
                XCTAssertFalse(
                    text.contains(phrase),
                    "週次分析の文言に禁止句が入っている: 「\(text)」 に 「\(phrase)」"
                )
            }
        }
    }
}
