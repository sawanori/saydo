import Foundation
import SaydoCore
import SwiftData
import XCTest

@testable import Saydo

/// 保留中の通知の後始末の、記録するだけの実装。
@MainActor
private final class FakePendingNotifications: PendingNotificationClearing {
    private(set) var clears = 0

    func removeAllManagedPending() async {
        clears += 1
    }
}

/// `AppRouter` の入口の判定を見る（実装計画 §17.3 / §17.9、task_056・task_058）。
/// 回の時刻は既定（朝 8:00・昼 13:00・晩 21:00）。
/// 画面の頭脳（録音・文字起こしの実体が要る）は作らず、`cover` と判定の結果だけを確かめる。
@MainActor
final class AppRouterTests: XCTestCase {

    private var container: ModelContainer!
    private var repository: Repository!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var notifications: FakePendingNotifications!
    private var alarms: RecordingRoundAlarms!
    private var audioRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        container = try SaydoModelContainer.make(inMemory: true)
        repository = Repository(modelContainer: container)
        let suiteName = "AppRouterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AppSettings(defaults: defaults)
        settings.useRoundTimesOfTheAnswerTests()
        notifications = FakePendingNotifications()
        alarms = RecordingRoundAlarms()
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

    /// `createdAt` に約束する。追う回は約束の時刻で決まる（`plannedAt` は最初に追う回の時刻の写し）。
    @discardableResult
    private func makeCommitment(createdAt: Date, plannedAt: Date? = nil) async throws -> CommitmentSnapshot {
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

    /// 始まっている回の答えがまだの日の起動で、答える画面が出る。
    func testLaunchAfterARoundStartedShowsFollowUpScreen() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 13, 30))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .followUp(saved))
        XCTAssertEqual(router.cover, .followUp(saved))
    }

    /// 約束があって、最初の回が始まる前の日は、今日の画面のまま。
    func testPromiseBeforeTheFirstRoundShowsToday() async throws {
        try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 9, 30))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .today)
        XCTAssertNil(router.cover)
        XCTAssertTrue(router.hasResolvedEntry)
    }

    /// 約束より前の回（9 時の約束に対する朝 8:00 の回）は、答えを待つ回に数えない。
    func testARoundBeforeThePromiseIsNotAwaited() async throws {
        try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 12, 59))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .today)
    }

    /// アラームの「開く」の合図があれば、答える画面が出る（回の時刻ちょうどの時計のずれを含む）。
    func testOpenSignalShowsFollowUpScreen() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 12, 59))

        let withoutSignal = await router.resolveEntry()
        XCTAssertEqual(withoutSignal, .today)
        XCTAssertNil(router.cover)

        let withSignal = await router.resolveEntry(openRequested: true)
        XCTAssertEqual(withSignal, .followUp(saved))
        XCTAssertEqual(router.cover, .followUp(saved))
    }

    /// 「開く」の合図があっても、答える約束が無ければ答える画面は出さない（朝の回の「開く」は約束する画面）。
    func testOpenSignalWithoutPromiseFallsBackToPromiseScreen() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))

        let destination = await router.resolveEntry(openRequested: true)

        XCTAssertEqual(destination, .promise)
    }

    /// 「やった」と答えた日は、「開く」の合図があっても今日の画面。
    func testDonePromiseShowsToday() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        try await repository.updateOutcome(commitmentID: saved.id, outcome: .done)
        let router = makeRouter(now: try date(2026, 10, 6, 14))

        let destination = await router.resolveEntry(openRequested: true)

        XCTAssertEqual(destination, .today)
        XCTAssertNil(router.cover)
    }

    /// 「今日はやめる」と答えた日（全部の回を答えたことにする）は、晩の回の時刻を過ぎても今日の画面。
    func testStoppedPromiseIsNotFollowedUpAgain() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        try await repository.updateOutcome(commitmentID: saved.id, outcome: .notYet)
        settings.markRoundsAnswered(Set(AlarmRound.allCases), on: saved.dayKey)
        let router = makeRouter(now: try date(2026, 10, 6, 21, 30))

        let destination = await router.resolveEntry(openRequested: true)

        XCTAssertEqual(destination, .today)
    }

    /// 昼の回に「まだ」と答えた後、晩の回の時刻を過ぎると、また答える画面が出る（§17.9 の 3）。
    func testAfterNotYetAtNoonTheEveningRoundAsksAgain() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let answered = try await repository.updateOutcome(commitmentID: saved.id, outcome: .notYet)
        settings.markRoundsAnswered([.noon], on: saved.dayKey)

        let afternoon = makeRouter(now: try date(2026, 10, 6, 14))
        let afternoonDestination = await afternoon.resolveEntry()
        XCTAssertEqual(afternoonDestination, .today, "昼の回は答えた。晩の回はまだ始まっていない")

        let evening = makeRouter(now: try date(2026, 10, 6, 21, 5))
        let eveningDestination = await evening.resolveEntry()
        XCTAssertEqual(eveningDestination, .followUp(answered))
    }

    /// 前日の深夜（最後の回を過ぎた後）に約束した日は、追う回が無い。答える画面には出ず、翌日は新しい約束になる。
    func testPromiseMadeLateLastNightIsNotCarriedIntoToday() async throws {
        try await makeCommitment(createdAt: try date(2026, 10, 5, 23, 45))

        for (hour, minute) in [(0, 40), (8, 30)] {
            let router = makeRouter(now: try date(2026, 10, 6, hour, minute))
            let destination = await router.resolveEntry()
            XCTAssertEqual(destination, .promise, "\(hour):\(minute) は新しい約束をする画面（昨夜の約束の答えは求めない）")
        }
    }

    /// 昨日のうちに追い終えた約束（答えないまま日付が変わった）は、翌日に蒸し返さない。
    func testYesterdaysUnansweredPromiseIsNotBroughtBack() async throws {
        try await makeCommitment(createdAt: try date(2026, 10, 5, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 7))

        let destination = await router.resolveEntry()

        XCTAssertEqual(destination, .promise)
    }

    /// 同じ画面を出している間に前面へ戻っても、画面を作り直さない。
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
    }

    /// 全削除の後はオンボーディングに戻り、答える先の無いアラームを残さない。
    func testResetReturnsToOnboardingAndCancelsEveryAlarm() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 9))
        await router.resolveEntry()
        await router.refreshAlarms()
        await alarms.clearEvents()
        settings.reset()

        router.reloadOnboardingState()

        XCTAssertFalse(router.hasCompletedOnboarding)
        XCTAssertNil(router.cover)
        for _ in 0..<200 {
            if await alarms.events.contains(.cancelAll) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let events = await alarms.events
        XCTAssertEqual(events, [.cancelAll])
        let registered = await alarms.registered
        XCTAssertTrue(registered.isEmpty)
    }

    // MARK: 約束する画面を閉じる

    /// 朝の回が始まる前に本人が閉じた後は、起動のたびに出し直さない。今日の画面の主ボタンからは開ける。
    func testClosingPromiseBeforeTheMorningRoundDoesNotReopenOnNextLaunch() async throws {
        let now = try date(2026, 10, 6, 7)
        let router = makeRouter(now: now)
        await router.resolveEntry()

        await router.closePromise()

        XCTAssertNil(router.cover)
        XCTAssertEqual(router.generation, 1)

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

    /// 約束の無い朝の回の時刻を過ぎて開くと、その日に閉じた後でも約束する画面が出る（§17.9 の 5）。
    func testOpeningAfterTheMorningRoundWithoutAPromiseShowsPromiseScreen() async throws {
        let early = makeRouter(now: try date(2026, 10, 6, 7))
        await early.resolveEntry()
        await early.closePromise()

        let afterMorning = makeRouter(now: try date(2026, 10, 6, 8, 5))
        let destination = await afterMorning.resolveEntry()

        XCTAssertEqual(destination, .promise)
        XCTAssertTrue(isPromise(afterMorning.cover))
    }

    /// 約束の無い朝に「今日はやめる」と答えた日は、朝の回の時刻を過ぎても約束する画面を出し直さない。
    func testStoppingTheMorningRoundKeepsThePromiseScreenClosed() async throws {
        let now = try date(2026, 10, 6, 8, 5)
        let router = makeRouter(now: now)
        await router.resolveEntry()
        XCTAssertTrue(isPromise(router.cover))

        await router.chase.stopMorningPrompt()
        await router.closePromise()

        let nextLaunch = makeRouter(now: try date(2026, 10, 6, 8, 30))
        let destination = await nextLaunch.resolveEntry()
        XCTAssertEqual(destination, .today)
        let today = await alarms.rounds(on: now)
        XCTAssertEqual(today, [], "その日の朝の回は止まる")
    }

    /// 閉じた日の翌日は、また約束する画面が出る。
    func testPromiseScreenReturnsTheNextDay() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 7))
        await router.resolveEntry()
        await router.closePromise()

        let nextDay = makeRouter(now: try date(2026, 10, 7, 7))
        let destination = await nextDay.resolveEntry()

        XCTAssertEqual(destination, .promise)
    }

    // MARK: アラームの登録し直し

    /// 約束の無い日の起動: 今日と翌日の朝の回（約束を促す、既定の音）を登録する。
    /// これまでの朝の通知 1 通は登録せず、旧い版の保留中の通知は取り消す（§17.9 の 5・6）。
    func testRefreshRegistersTheMorningPromptForTodayAndTomorrow() async throws {
        let now = try date(2026, 10, 6, 7)
        let router = makeRouter(now: now)

        await router.refreshAlarms()

        XCTAssertEqual(notifications.clears, 1)
        let today = await alarms.request(.morning, on: now)
        XCTAssertEqual(
            today,
            AlarmRoundRequest(round: .morning, start: try date(2026, 10, 6, 8), voiceRelativePath: nil, purpose: .prompt)
        )
        let todayRounds = await alarms.rounds(on: now)
        XCTAssertEqual(todayRounds, [.morning])
        let tomorrow = await alarms.request(.morning, on: try date(2026, 10, 7, 12))
        XCTAssertEqual(tomorrow?.start, try date(2026, 10, 7, 8))
        XCTAssertEqual(tomorrow?.purpose, .prompt)
    }

    /// 旧い識別子で登録済みのアラームは、最初の登録し直しで 1 度だけ取り消す。
    func testLegacyAlarmsAreClearedOnlyOnce() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 7))

        await router.refreshAlarms()
        await router.refreshAlarms()
        let relaunched = makeRouter(now: try date(2026, 10, 6, 7))
        await relaunched.refreshAlarms()

        let events = await alarms.events
        XCTAssertEqual(events.filter { $0 == .cancelAll }.count, 1)
        XCTAssertEqual(events.first, .cancelAll)
        XCTAssertTrue(settings.legacyAlarmsCleared)
    }

    /// 約束のある日の起動: まだ答えていない回を本人の声で登録し、翌日の朝の回も登録する。
    func testRefreshRegistersTheRemainingRoundsOfThePromise() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        settings.markRoundsAnswered([.noon], on: saved.dayKey)
        let now = try date(2026, 10, 6, 14)
        let router = makeRouter(now: now)

        await router.refreshAlarms()

        let today = await alarms.rounds(on: now)
        XCTAssertEqual(today, [.evening])
        let evening = await alarms.request(.evening, on: now)
        XCTAssertEqual(evening?.purpose, .chase)
        let tomorrow = await alarms.rounds(on: try date(2026, 10, 7, 12))
        XCTAssertEqual(tomorrow, [.morning])
    }

    /// 同じ内容を登録済みなら、前面に戻るたびに並べ直さない。設定の時刻を変えたら登録し直す。
    func testRefreshReappliesOnlyWhenThePlanChanges() async throws {
        let now = try date(2026, 10, 6, 7)
        let router = makeRouter(now: now)
        await router.refreshAlarms()
        let first = await alarms.scheduleCalls

        await router.refreshAlarms()
        let second = await alarms.scheduleCalls
        XCTAssertEqual(second, first)

        settings.morningTime = TimeOfDay(hour: 7, minute: 30)
        await router.refreshAlarms()
        let today = await alarms.request(.morning, on: now)
        XCTAssertEqual(today?.start, try date(2026, 10, 6, 7, 30))
        let tomorrow = await alarms.request(.morning, on: try date(2026, 10, 7, 12))
        XCTAssertEqual(tomorrow?.start, try date(2026, 10, 7, 7, 30))
    }

    // MARK: 通知のタップ（旧い版が登録した通知）

    /// 通知をタップしたら、起動時と同じ判定で開く。その日に閉じていても、約束が無ければ約束する画面。
    func testNotificationTapOpensPromiseScreenEvenAfterDismissal() async throws {
        let router = makeRouter(now: try date(2026, 10, 6, 7))
        await router.resolveEntry()
        await router.closePromise()
        XCTAssertNil(router.cover)

        await router.openFromLegacyNotification()

        XCTAssertTrue(isPromise(router.cover))
    }

    /// 通知をタップした時点で答えがまだなら、答える画面（7 時の約束は、朝 8:00 の回も結果を聞く回になる）。
    func testNotificationTapShowsFollowUpWhenAnswerIsPending() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 7))
        let router = makeRouter(now: try date(2026, 10, 6, 8))

        await router.openFromLegacyNotification()

        XCTAssertEqual(router.cover, .followUp(saved))
    }

    // MARK: 答える画面

    func testTodayButtonOpensFollowUpAndClosingReturnsToToday() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))
        let router = makeRouter(now: try date(2026, 10, 6, 13, 30))

        router.openFollowUp(for: saved)
        XCTAssertEqual(router.cover, .followUp(saved))

        router.closeFollowUp()
        XCTAssertNil(router.cover)
        XCTAssertEqual(router.generation, 1)
    }

    // MARK: 判定（純粋な部分）

    func testDestinationPrefersFollowUpOverPromise() async throws {
        let saved = try await makeCommitment(createdAt: try date(2026, 10, 6, 9))

        func destination(
            onboarded: Bool = true, open: Bool = false,
            awaiting: CommitmentSnapshot? = nil, inPlay: CommitmentSnapshot? = nil,
            roundsLeft: Bool = false, dismissed: Bool = false, promptDue: Bool = false
        ) -> AppRouter.Destination {
            AppRouter.destination(
                hasCompletedOnboarding: onboarded, openRequested: open,
                awaiting: awaiting, inPlay: inPlay, inPlayHasRoundsLeft: roundsLeft,
                promiseDismissedToday: dismissed, morningPromptDue: promptDue
            )
        }

        XCTAssertEqual(destination(onboarded: false, open: true, awaiting: saved, inPlay: saved), .onboarding)
        XCTAssertEqual(destination(awaiting: saved), .followUp(saved))
        XCTAssertEqual(destination(dismissed: true), .today)
        XCTAssertEqual(destination(dismissed: true, promptDue: true), .promise)
        XCTAssertEqual(destination(open: true, dismissed: true), .promise)
        XCTAssertEqual(destination(open: true, inPlay: saved, roundsLeft: true), .followUp(saved))
        XCTAssertEqual(destination(open: true, inPlay: saved, roundsLeft: false), .today)
        // 約束のある日は、朝の回の時刻を過ぎていても約束する画面は出さない。
        XCTAssertEqual(destination(inPlay: saved, roundsLeft: true, promptDue: true), .today)
    }
}
