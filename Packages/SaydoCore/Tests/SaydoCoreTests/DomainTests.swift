import Foundation
import XCTest

@testable import SaydoCore

final class DomainTests: XCTestCase {

    // MARK: - SessionType

    func testSessionTypeCoversFourSessions() {
        XCTAssertEqual(SessionType.allCases.map(\.rawValue), ["morning", "noon", "night", "adhoc"])
    }

    func testSessionTypeDisplayNames() {
        XCTAssertEqual(SessionType.allCases.map(\.displayName), ["朝", "昼", "夜", "手動"])
    }

    // MARK: - ReasonCategory

    func testReasonCategoryHasSevenCases() {
        XCTAssertEqual(ReasonCategory.allCases.count, 7)
    }

    func testReasonCategoryDisplayNames() {
        XCTAssertEqual(
            ReasonCategory.allCases.map(\.displayName),
            ["気まずい", "完璧にやりたい", "面倒", "不安・怖い", "量が多い", "何から始めるかわからない", "期限が怖い"]
        )
    }

    // MARK: - TaskDomain

    func testTaskDomainHasSevenCases() {
        XCTAssertEqual(TaskDomain.allCases.count, 7)
    }

    func testTaskDomainDisplayNames() {
        XCTAssertEqual(
            TaskDomain.allCases.map(\.displayName),
            ["人への返信", "お金", "大きなタスク", "営業", "書類", "健康", "その他"]
        )
    }

    // MARK: - CommitmentOutcome

    func testCommitmentOutcomeDisplayNames() {
        XCTAssertEqual(
            CommitmentOutcome.allCases.map(\.displayName),
            ["未確認", "やった", "少しやった", "まだ"]
        )
    }

    /// 企画原則 §22-7「未達成より『少し進んだ』を評価する」。partial は前進として扱う。
    func testPartialCountsAsProgress() {
        XCTAssertTrue(CommitmentOutcome.done.isProgress)
        XCTAssertTrue(CommitmentOutcome.partial.isProgress)
        XCTAssertFalse(CommitmentOutcome.notYet.isProgress)
        XCTAssertFalse(CommitmentOutcome.pending.isProgress)
    }

    // MARK: - FlowStep

    func testFlowStepCodesAreUnique() {
        let codes = FlowStep.allCases.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count)
        XCTAssertEqual(FlowStep.allCases.count, 12)
    }

    func testFlowStepDisplayNamesAreNotEmpty() {
        for step in FlowStep.allCases {
            XCTAssertFalse(step.displayName.isEmpty, "\(step.code) に表示名がない")
        }
    }

    func testFlowStepsPerSession() {
        XCTAssertEqual(FlowStep.steps(for: .morning).map(\.code), ["M0", "M1", "M2", "M3", "M4"])
        XCTAssertEqual(FlowStep.steps(for: .noon).map(\.code), ["N0", "N1", "N2", "N3"])
        XCTAssertEqual(FlowStep.steps(for: .night).map(\.code), ["E0", "E1"])
        XCTAssertEqual(FlowStep.steps(for: .adhoc), [])
    }

    func testFlowStepSessionTypeMapping() {
        for sessionType in [SessionType.morning, .noon, .night] {
            for step in FlowStep.steps(for: sessionType) {
                XCTAssertEqual(step.sessionType, sessionType, "\(step.code) の所属が違う")
            }
        }
        XCTAssertNil(FlowStep.finished.sessionType)
    }

    // MARK: - MicroAction

    func testMicroActionDefaultsAndShrink() {
        let action = MicroAction(text: "hello")
        XCTAssertEqual(action.estimatedMinutes, 5)
        XCTAssertEqual(action.shrinkCount, 0)
        XCTAssertTrue(action.isFiveMinutesOrLess)

        let smaller = action.shrunk(to: "smaller", estimatedMinutes: 2)
        XCTAssertEqual(smaller.shrinkCount, 1)
        XCTAssertEqual(smaller.estimatedMinutes, 2)
        XCTAssertEqual(smaller.text, "smaller")
    }

    // MARK: - WeeklyStats

    func testWeeklyStatsRanksDomainsAndReasons() {
        let stats = WeeklyStats(
            weekStart: Date(timeIntervalSince1970: 0),
            domainCounts: [.reply: 3, .money: 5, .health: 0, .paperwork: 3],
            reasonRatios: [.awkward: 0.5, .tedious: 0.25, .anxious: 0.25, .tooMuch: 0]
        )
        XCTAssertEqual(stats.totalCount, 11)
        // 件数の降順、同数は rawValue の昇順（paperwork < reply）。
        XCTAssertEqual(stats.topDomains(), [.money, .paperwork, .reply])
        XCTAssertEqual(stats.topDomains(limit: 1), [.money])
        // 割合の降順、同率は rawValue の昇順（anxious < tedious）。
        XCTAssertEqual(stats.topReasons(), [.awkward, .anxious, .tedious])
    }

    // MARK: - Codable

    func testDomainValuesRoundTripThroughJSON() throws {
        let context = DialogueContext(
            sessionType: .noon,
            step: .noonShrink,
            avoidance: "avoidance",
            reason: .anxious,
            domain: .money,
            microAction: MicroAction(text: "open it", estimatedMinutes: 3, shrinkCount: 1),
            blocker: "blocker",
            carryover: "carryover",
            outcome: .partial
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(DialogueContext.self, from: encoder.encode(context)), context)

        let classification = ReasonClassification(category: .perfectionism, followUp: "followUp")
        XCTAssertEqual(
            try decoder.decode(ReasonClassification.self, from: encoder.encode(classification)),
            classification
        )

        let stats = WeeklyStats(
            weekStart: Date(timeIntervalSince1970: 1_756_944_000),
            domainCounts: [.sales: 2],
            reasonRatios: [.deadlineFear: 1.0]
        )
        XCTAssertEqual(try decoder.decode(WeeklyStats.self, from: encoder.encode(stats)), stats)
    }
}
