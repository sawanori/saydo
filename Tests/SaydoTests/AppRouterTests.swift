import Foundation
import SaydoCore
import SwiftData
import XCTest

@testable import Saydo

/// `AppRouter` の経路だけを見る。`SessionViewModel` の生成（音声スタックの実体が要る）は
/// `beginSession()` の中なので、ここでは呼ばない。
@MainActor
final class AppRouterTests: XCTestCase {

    private var container: ModelContainer!
    private var repository: Repository!
    private var defaults: UserDefaults!
    private var settings: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        container = try SaydoModelContainer.make(inMemory: true)
        repository = Repository(modelContainer: container)
        let suiteName = "AppRouterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        settings.reset()
        settings = nil
        defaults = nil
        repository = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func makeRouter(now: Date) -> AppRouter {
        AppRouter(
            modelContainer: container,
            settings: settings,
            now: { now }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        )
    }

    @discardableResult
    private func makeCommitment(at date: Date) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(
            CommitmentDraft(
                avoidanceTitle: "invoice",
                microAction: MicroAction(text: "open", estimatedMinutes: 2),
                plannedAt: date,
                declarationTranscript: "declaration",
                createdAt: date
            )
        )
    }

    // MARK: 通知から開く

    func testOpenLinkStartsMatchingSession() throws {
        let router = makeRouter(now: try date(2026, 9, 4, 13))
        let commitmentID = UUID()

        router.launch(
            DeepLink(
                sessionType: .noon,
                slot: .action,
                commitmentID: commitmentID,
                copyKey: .action,
                action: .open
            )
        )

        let session = try XCTUnwrap(router.activeSession)
        XCTAssertEqual(session.sessionType, .noon)
        XCTAssertEqual(session.commitmentID, commitmentID)
        XCTAssertEqual(session.source, .notification)
        // 会話画面が出るまで `SessionViewModel` は作らない。
        XCTAssertNil(router.sessionViewModel)
    }

    func testRestLinkDoesNotOpenAnything() throws {
        let router = makeRouter(now: try date(2026, 9, 4, 13))

        router.launch(DeepLink(sessionType: .noon, slot: .noon, action: .rest))

        XCTAssertNil(router.activeSession)
    }

    func testMorningLinkKeepsMorningSessionType() throws {
        let router = makeRouter(now: try date(2026, 9, 4, 8))

        router.launch(DeepLink(sessionType: .morning, slot: .morning, copyKey: .morning, action: .open))

        XCTAssertEqual(router.activeSession?.sessionType, .morning)
        XCTAssertNil(router.activeSession?.commitmentID)
    }

    // MARK: 手動で開く

    func testManualSessionWithoutTodayCommitmentOpensMorning() async throws {
        let router = makeRouter(now: try date(2026, 9, 4, 10))

        await router.startManualSession()

        let session = try XCTUnwrap(router.activeSession)
        XCTAssertEqual(session.sessionType, .morning)
        XCTAssertNil(session.commitmentID)
        XCTAssertEqual(session.source, .manual)
    }

    func testManualSessionWithTodayCommitmentOpensAdhoc() async throws {
        let today = try date(2026, 9, 4, 10)
        let saved = try await makeCommitment(at: today)
        let router = makeRouter(now: today)

        await router.startManualSession()

        let session = try XCTUnwrap(router.activeSession)
        XCTAssertEqual(session.sessionType, .adhoc)
        XCTAssertEqual(session.commitmentID, saved.id)
    }

    // MARK: 閉じる

    func testDismissClearsActiveSession() throws {
        let router = makeRouter(now: try date(2026, 9, 4, 13))
        router.launch(DeepLink(sessionType: .noon, slot: .noon, action: .open))
        XCTAssertNotNil(router.activeSession)

        router.dismissSession()

        XCTAssertNil(router.activeSession)
        XCTAssertNil(router.sessionViewModel)
    }

    // MARK: オンボーディング

    func testCompleteOnboardingIsRemembered() throws {
        let router = makeRouter(now: try date(2026, 9, 4, 8))
        XCTAssertFalse(router.hasCompletedOnboarding)

        router.completeOnboarding()

        XCTAssertTrue(router.hasCompletedOnboarding)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }
}
