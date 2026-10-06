import Foundation
import SaydoCore
import SwiftData
import UserNotifications
import XCTest

@testable import Saydo

/// 朝の通知の、記録するだけの実装。許可のダイアログは出さない。
@MainActor
private final class FakeMorningNotifications: MorningNotifying {
    var status: UNAuthorizationStatus
    private(set) var authorizationRequests = 0
    /// 登録し直しのたびに、その時点で今日の約束があったかを残す。
    private(set) var reschedules: [Bool] = []

    init(status: UNAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        status = .authorized
        return true
    }

    func rescheduleMorning(now: Date, settings: SaydoCore.NotificationSettings, hasPromiseToday: Bool) async {
        reschedules.append(hasPromiseToday)
    }
}

/// `AlarmScheduling` の記録するだけの実装。AlarmKit には触らない。
private actor RecordingAlarms: AlarmScheduling {
    private(set) var cancelledDays: [Date] = []

    func requestAuthorization() async -> Bool { true }

    func scheduleChain(start: Date, voiceRelativePath: String?) async -> AlarmScheduleOutcome {
        .scheduled(count: AlarmPlan.defaultCount)
    }

    func cancelChain(startedOn day: Date) async {
        cancelledDays.append(day)
    }
}

/// `AppRouter` の入口の判定を見る（実装計画 §17.3、task_056）。
/// 画面の頭脳（録音・文字起こしの実体が要る）は作らず、`cover` と判定の結果だけを確かめる。
@MainActor
final class AppRouterTests: XCTestCase {

    private var container: ModelContainer!
    private var repository: Repository!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var notifications: FakeMorningNotifications!
    private var alarms: RecordingAlarms!
    private var audioRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        container = try SaydoModelContainer.make(inMemory: true)
        repository = Repository(modelContainer: container)
        let suiteName = "AppRouterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AppSettings(defaults: defaults)
        notifications = FakeMorningNotifications()
        alarms = RecordingAlarms()
        audioRoot = FileManager.default.temporaryDirectory
            .appending(path: "AppRouterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        settings.reset()
        try? FileManager.default.removeItem(at: audioRoot)
        settings = nil
        defaults = nil
        repository = nil
        container = nil
        notifications = nil
        alarms = nil
        audioRoot = nil
        try await super.tearDown()
    }

    // MARK: 補助

    /// オンボーディングを終えた状態のルーター。`onboarded: false` で初回の状態にする。
    private func makeRouter(now: Date, onboarded: Bool = true) -> AppRouter {
        settings.hasCompletedOnboarding = onboarded
        return AppRouter(
            modelContainer: container,
            notifications: notifications,
            alarms: alarms,
            audioFiles: AudioFileStore(rootDirectory: audioRoot),
            settings: settings,
            now: { now }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
            )
        )
    }

    /// `createdAt` に約束し、`plannedAt` から追い始める約束を作る。
    @discardableResult
    private func makeCommitment(createdAt: Date, plannedAt: Date) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(
            CommitmentDraft(
                avoidanceTitle: "invoice",
                microAction: MicroAction(text: "open"),
                plannedAt: plannedAt,
                declarationTranscript: "invoice。open",
                createdAt: createdAt
            )
        )
    }

    private func isPromise(_ cover: AppRouter.Cover?) -> Bool {
        if case .promise = cover { return true }
        return false
    }

    // MARK: 起動時の判定

    /// done_definition: 約束の無い日の起動で約束する画面が出る。
    func testLaunchWithoutPromiseShowsPromiseScreen() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))
        XCTAssertFalse(router.hasResolvedEntry)

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .promise)
        XCTAssertTrue(isPromise(router.cover))
        XCTAssertTrue(router.hasResolvedEntry)
    }

    /// done_definition: 追い始めた後で答えがまだの日の起動で答える画面が出る。
    func testLaunchAfterChaseStartedShowsFollowUpScreen() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 9),
            plannedAt: try date(2026, 10, 6, 10)
        )
        let router = makeRouter(now: try date(2026, 10, 6, 10, 30))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .followUp(saved))
        XCTAssertEqual(router.cover, .followUp(saved))
    }

    /// 約束があって追い始める前の日は、今日の画面のまま。
    func testPromiseBeforeChaseStartsShowsToday() async throws {
        try await makeCommitment(createdAt: try date(2026, 10, 6, 9), plannedAt: try date(2026, 10, 6, 10))
        let router = makeRouter(now: try date(2026, 10, 6, 9, 30))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .today)
        XCTAssertNil(router.cover)
        XCTAssertTrue(router.hasResolvedEntry)
    }

    /// アラームの「開く」の合図があれば、答える画面が出る（追い始める時刻ちょうどの時計のずれを含む）。
    func testOpenSignalShowsFollowUpScreen() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 9),
            plannedAt: try date(2026, 10, 6, 10)
        )
        let router = makeRouter(now: try date(2026, 10, 6, 9, 59))

        let withoutSignal = await router.resolveEntry()
        XCTAssertEqual(withoutSignal, .today)
        XCTAssertNil(router.cover)

        let withSignal = await router.resolveEntry(openRequested: true)
        XCTAssertEqual(withSignal, .followUp(saved))
        XCTAssertEqual(router.cover, .followUp(saved))
    }

    /// 「開く」の合図があっても、答える約束が無ければ答える画面は出さない。
    func testOpenSignalWithoutPromiseFallsBackToPromiseScreen() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))

        let destination = await router.resolveEntry(openRequested: true)

        XCTAssertEqual(destination, .promise)
    }

    /// 答え終えた日は、今日の画面。
    func testAnsweredPromiseShowsToday() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 9),
            plannedAt: try date(2026, 10, 6, 10)
        )
        try await repository.updateOutcome(commitmentID: saved.id, outcome: .partial)
        let router = makeRouter(now: try date(2026, 10, 6, 11))

        let destination = await router.resolveEntry(openRequested: true)

        XCTAssertEqual(destination, .today)
        XCTAssertNil(router.cover)
    }

    /// 前日の深夜に約束して、追い始める時刻が今日になった約束。追い始める前は今日の画面
    /// （約束する画面を出して 2 件目を作らせない）、追い始めた後は答える画面。
    func testPromiseMadeLateLastNightIsStillInPlay() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 5, 23, 30),
            plannedAt: try date(2026, 10, 6, 0, 30)
        )

        let before = makeRouter(now: try date(2026, 10, 6, 0, 10))
        let beforeDestination = await before.resolveEntry()
        XCTAssertEqual(beforeDestination, .today)

        let after = makeRouter(now: try date(2026, 10, 6, 0, 40))
        let afterDestination = await after.resolveEntry()
        XCTAssertEqual(afterDestination, .followUp(saved))
    }

    /// 同じ答える画面を出している間に前面へ戻っても、画面を作り直さない。
    func testResolvingAgainKeepsTheSameCover() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))
        await router.resolveEntry()
        let first = router.cover

        await router.resolveEntry()

        XCTAssertEqual(router.cover, first)
    }

    // MARK: オンボーディング

    func testLaunchBeforeOnboardingShowsOnboarding() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9), onboarded: false)

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .onboarding)
        XCTAssertNil(router.cover)
        XCTAssertFalse(router.hasCompletedOnboarding)
    }

    /// done_definition: オンボーディングを終えると約束する画面が出る。
    func testCompletingOnboardingShowsPromiseScreen() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9), onboarded: false)

        await router.completeOnboarding()

        XCTAssertTrue(router.hasCompletedOnboarding)
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertTrue(isPromise(router.cover))
        // 通知の許可は、オンボーディングでは求めない。
        XCTAssertEqual(notifications.authorizationRequests, 0)
    }

    /// 全削除の後はオンボーディングに戻り、答える先の無いアラームを残さない。
    func testResetReturnsToOnboardingAndCancelsChains() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))
        await router.resolveEntry()
        settings.reset()

        router.reloadOnboardingState()

        XCTAssertFalse(router.hasCompletedOnboarding)
        XCTAssertNil(router.cover)
        for _ in 0..<200 {
            if await alarms.cancelledDays.count == 3 { break }
            await Task.yield()
        }
        let cancelled = await alarms.cancelledDays
        XCTAssertEqual(cancelled.count, 3)
    }

    // MARK: 約束する画面を閉じる

    /// その日に本人が閉じた後は、起動のたびに出し直さない。今日の画面の主ボタンと朝の通知からは開ける。
    func testClosingPromiseWithoutSavingDoesNotReopenOnNextLaunch() async throws {
        let now = try date(2026, 10, 6, 9)
        let router = makeRouter(now: now)
        await router.resolveEntry()

        await router.closePromise()

        XCTAssertNil(router.cover)
        XCTAssertEqual(router.generation, 1)
        // 約束を保存していないので、通知の許可は求めない。
        XCTAssertEqual(notifications.authorizationRequests, 0)

        let nextLaunch = makeRouter(now: now)
        let destination = await nextLaunch.resolveEntry()
        XCTAssertEqual(destination, .today)
        XCTAssertNil(nextLaunch.cover)

        nextLaunch.openPromise()
        XCTAssertTrue(isPromise(nextLaunch.cover))
        let manual = nextLaunch.cover

        // 自分で開いた約束する画面は、前面に戻ったときの判定で閉じられない。
        await nextLaunch.resolveEntry()
        XCTAssertEqual(nextLaunch.cover, manual)
    }

    /// 閉じた日の翌日は、また約束する画面が出る。
    func testPromiseScreenReturnsTheNextDay() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))
        await router.resolveEntry()
        await router.closePromise()

        let nextDay = makeRouter(now: try date(2026, 10, 7, 9))
        let destination = await nextDay.resolveEntry()

        XCTAssertEqual(destination, .promise)
    }

    /// 通知の許可は、最初の約束が保存された後に求める。朝の 1 通は、今日の分を外して登録し直す。
    func testNotificationPermissionIsRequestedAfterTheFirstPromiseIsSaved() async throws {
        let now = try date(2026, 10, 6, 9)
        let router = makeRouter(now: now)
        await router.resolveEntry()
        XCTAssertEqual(notifications.authorizationRequests, 0)

        try await makeCommitment(createdAt: now, plannedAt: try date(2026, 10, 6, 10))
        await router.closePromise()

        XCTAssertNil(router.cover)
        XCTAssertEqual(notifications.authorizationRequests, 1)
        XCTAssertEqual(notifications.reschedules, [true])

        // 2 回目からは求めない。
        let later = makeRouter(now: now)
        later.openPromise()
        await later.closePromise()
        XCTAssertEqual(notifications.authorizationRequests, 1)
    }

    // MARK: 朝の通知

    /// 朝の通知をタップしたら、起動時と同じ判定で開く。その日に閉じていても、約束が無ければ約束する画面。
    func testMorningNotificationTapOpensPromiseScreenEvenAfterDismissal() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 8))
        await router.resolveEntry()
        await router.closePromise()
        XCTAssertNil(router.cover)

        await router.open(DeepLink(sessionType: .morning, slot: .morning, copyKey: .morning, action: .open))

        XCTAssertTrue(isPromise(router.cover))
    }

    /// 朝の通知をタップした時点で答えがまだなら、答える画面。
    func testNotificationTapShowsFollowUpWhenAnswerIsPending() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 7),
            plannedAt: try date(2026, 10, 6, 7, 30)
        )
        let router = makeRouter(now: try date(2026, 10, 6, 8))

        await router.open(DeepLink(sessionType: .morning, slot: .morning, copyKey: .morning, action: .open))

        XCTAssertEqual(router.cover, .followUp(saved))
    }

    /// 「今日は休む」は何も開かない。
    func testRestLinkDoesNotOpenAnything() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 8))

        await router.open(DeepLink(sessionType: .morning, slot: .morning, action: .rest))

        XCTAssertNil(router.cover)
    }

    /// 通知が許可されていなければ登録しない。許可されていれば、朝の 1 通だけを登録し直す。
    func testMorningNotificationIsRefreshedOnlyWhenAuthorized() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))

        await router.refreshMorningNotification()
        XCTAssertTrue(notifications.reschedules.isEmpty)
        XCTAssertEqual(notifications.authorizationRequests, 0)

        notifications.status = .authorized
        await router.refreshMorningNotification()
        XCTAssertEqual(notifications.reschedules, [false])
    }

    // MARK: 答える画面

    func testTodayButtonOpensFollowUpAndClosingReturnsToToday() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 9),
            plannedAt: try date(2026, 10, 6, 10)
        )
        let router = makeRouter(now: try date(2026, 10, 6, 10, 30))

        router.openFollowUp(for: saved)
        XCTAssertEqual(router.cover, .followUp(saved))

        router.closeFollowUp()
        XCTAssertNil(router.cover)
        XCTAssertEqual(router.generation, 1)
    }

    // MARK: 判定（純粋な部分）

    func testDestinationPrefersFollowUpOverPromise() async throws {
        let saved = try await makeCommitment(
            createdAt: try date(2026, 10, 6, 9),
            plannedAt: try date(2026, 10, 6, 10)
        )

        XCTAssertEqual(
            AppRouter.destination(
                hasCompletedOnboarding: false, openRequested: true,
                awaiting: saved, inPlay: saved, promiseDismissedToday: false
            ),
            .onboarding
        )
        XCTAssertEqual(
            AppRouter.destination(
                hasCompletedOnboarding: true, openRequested: false,
                awaiting: saved, inPlay: nil, promiseDismissedToday: false
            ),
            .followUp(saved)
        )
        XCTAssertEqual(
            AppRouter.destination(
                hasCompletedOnboarding: true, openRequested: false,
                awaiting: nil, inPlay: nil, promiseDismissedToday: true
            ),
            .today
        )
    }
}
