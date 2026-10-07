import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// `AlarmBackend` の記録するだけの実装。呼ばれた順に残す。
actor RecordingAlarmBackend: AlarmBackend {
    enum Event: Equatable, Sendable {
        case cancel(UUID)
        case schedule(id: UUID, fireDate: Date, soundName: String?, title: String)
    }

    struct Refused: Error {}

    private(set) var events: [Event] = []
    private(set) var authorizationRequests = 0
    /// いま登録されている識別子。実物と同じく、無い識別子の取り消しはエラーにする。
    private(set) var registered: Set<UUID> = []

    private var state: AlarmAuthorization
    private let stateAfterRequest: AlarmAuthorization
    /// この連番（0 始まり、登録の試行順）の登録を失敗させる。
    private var failingAttempts: Set<Int>
    private var failsEverySchedule: Bool
    private var attempts = 0
    /// 一覧（`scheduledIDs`）を失敗させるか。
    private var failsListing = false

    init(
        state: AlarmAuthorization = .authorized,
        stateAfterRequest: AlarmAuthorization = .authorized,
        failingAttempts: Set<Int> = [],
        failsEverySchedule: Bool = false
    ) {
        self.state = state
        self.stateAfterRequest = stateAfterRequest
        self.failingAttempts = failingAttempts
        self.failsEverySchedule = failsEverySchedule
    }

    func authorization() async -> AlarmAuthorization { state }

    func requestAuthorization() async -> AlarmAuthorization {
        authorizationRequests += 1
        if state == .notDetermined { state = stateAfterRequest }
        return state
    }

    func schedule(id: UUID, fireDate: Date, soundName: String?, title: String) async throws {
        let attempt = attempts
        attempts += 1
        if failsEverySchedule || failingAttempts.contains(attempt) { throw Refused() }
        registered.insert(id)
        events.append(.schedule(id: id, fireDate: fireDate, soundName: soundName, title: title))
    }

    func scheduledIDs() async throws -> [UUID] {
        if failsListing { throw Refused() }
        return Array(registered)
    }

    func failListing() {
        failsListing = true
    }

    /// 旧い版が登録したアラームなど、テストの外で登録されていたことにする。
    func seed(_ ids: [UUID]) {
        registered.formUnion(ids)
    }

    func cancel(id: UUID) async throws {
        events.append(.cancel(id))
        guard registered.remove(id) != nil else { throw Refused() }
    }

    var cancelledIDs: [UUID] {
        events.compactMap { if case .cancel(let id) = $0 { id } else { nil } }
    }

    var scheduled: [(id: UUID, fireDate: Date, soundName: String?, title: String)] {
        events.compactMap {
            if case .schedule(let id, let fireDate, let soundName, let title) = $0 {
                (id, fireDate, soundName, title)
            } else {
                nil
            }
        }
    }

    func clearEvents() {
        events = []
    }
}

final class AlarmSchedulerTests: XCTestCase {

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots where FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        temporaryRoots = []
        try super.tearDownWithError()
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    private func makeScheduler(
        backend: RecordingAlarmBackend,
        soundStore: AlarmSoundStore? = nil,
        now: Date
    ) -> AlarmScheduler {
        AlarmScheduler(backend: backend, soundStore: soundStore, calendar: tokyo, now: { now })
    }

    private func makeSoundStore() -> (store: AlarmSoundStore, audioFiles: AudioFileStore) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoAlarmSchedulerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryRoots.append(root)
        let audioFiles = AudioFileStore(rootDirectory: root.appending(path: "Audio", directoryHint: .isDirectory))
        let store = AlarmSoundStore(
            soundsDirectory: root.appending(path: "Sounds", directoryHint: .isDirectory),
            audioFileStore: audioFiles
        )
        return (store, audioFiles)
    }

    private func chase(
        _ round: AlarmRound,
        at start: Date,
        voice: String? = nil,
        title: String? = nil
    ) -> AlarmRoundRequest {
        AlarmRoundRequest(round: round, start: start, voiceRelativePath: voice, purpose: .chase, title: title)
    }

    // MARK: 登録

    func testScheduleRoundsCancelsTheWholeDayBeforeRegisteringEachRoundEveryThreeMinutes() async throws {
        let day = try date(6, 10)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)

        let outcome = await scheduler.scheduleRounds(
            [chase(.noon, at: try date(6, 13)), chase(.evening, at: try date(6, 21))],
            on: day
        )

        XCTAssertEqual(outcome, .scheduled(count: 80))
        let events = await backend.events
        let dayIDs = AlarmPlan.allIdentifiers(on: day, calendar: tokyo)
        XCTAssertEqual(dayIDs.count, 160)

        // 先頭が、その日の全識別子（3 回 + 追加の 1 回）の取り消し。登録はその後にだけ並ぶ。
        XCTAssertEqual(Array(events.prefix(160)), dayIDs.map { .cancel($0) })
        let registrations = Array(events.dropFirst(160))
        XCTAssertEqual(registrations.count, 80)
        let noonIDs = AlarmPlan.identifiers(on: day, round: .noon, calendar: tokyo)
        let eveningIDs = AlarmPlan.identifiers(on: day, round: .evening, calendar: tokyo)
        for index in 0..<40 {
            XCTAssertEqual(
                registrations[index],
                .schedule(
                    id: noonIDs[index],
                    fireDate: try date(6, 13).addingTimeInterval(180 * Double(index)),
                    soundName: nil,
                    title: PromiseCopy.alarmTitle
                )
            )
            XCTAssertEqual(
                registrations[40 + index],
                .schedule(
                    id: eveningIDs[index],
                    fireDate: try date(6, 21).addingTimeInterval(180 * Double(index)),
                    soundName: nil,
                    title: PromiseCopy.alarmTitle
                )
            )
        }
        // 朝の回は頼んでいないので、登録されない。
        let registered = await backend.registered
        XCTAssertEqual(registered, Set(noonIDs + eveningIDs))
    }

    func testScheduleRoundsReplacesWhatWasRegisteredOnTheSameDay() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        _ = await scheduler.scheduleRounds([chase(.morning, at: try date(6, 8))], on: day)

        let outcome = await scheduler.scheduleRounds([chase(.evening, at: try date(6, 21))], on: day)

        XCTAssertEqual(outcome, .scheduled(count: 40))
        let registered = await backend.registered
        XCTAssertEqual(registered, Set(AlarmPlan.identifiers(on: day, round: .evening, calendar: tokyo)))
    }

    func testScheduleRoundsUsesTheIntervalOfTheRequest() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        var request = chase(.morning, at: try date(6, 8))
        request.interval = 60

        _ = await makeScheduler(backend: backend, now: day).scheduleRounds([request], on: day)

        let fireDates = await backend.scheduled.map(\.fireDate)
        XCTAssertEqual(fireDates.count, 40)
        XCTAssertEqual(fireDates.last, try date(6, 8, 39))
    }

    func testScheduleRoundsSkipsTheSlotsThatHaveAlreadyPassed() async throws {
        let day = try date(6, 13, 7)
        let backend = RecordingAlarmBackend()
        // 13:07。13:00 / 13:03 / 13:06 は過ぎている。
        let scheduler = makeScheduler(backend: backend, now: day)

        let outcome = await scheduler.scheduleRounds([chase(.noon, at: try date(6, 13))], on: day)

        XCTAssertEqual(outcome, .scheduled(count: 37))
        let scheduled = await backend.scheduled
        XCTAssertEqual(scheduled.first?.fireDate, try date(6, 13, 9))
        XCTAssertEqual(scheduled.first?.id, AlarmPlan.identifier(on: day, round: .noon, index: 3, calendar: tokyo))
        XCTAssertTrue(scheduled.allSatisfy { $0.fireDate > day })
    }

    /// 回が空、または全部の本が過ぎているときは、その日を取り消すだけになる。
    func testScheduleRoundsWithNothingToRegisterOnlyCancelsTheDay() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        _ = await scheduler.scheduleRounds([chase(.morning, at: try date(6, 8))], on: day)

        let empty = await scheduler.scheduleRounds([], on: day)
        XCTAssertEqual(empty, .scheduled(count: 0))
        var registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)

        let late = makeScheduler(backend: backend, now: try date(6, 20))
        let passed = await late.scheduleRounds([chase(.noon, at: try date(6, 13))], on: day)
        XCTAssertEqual(passed, .scheduled(count: 0))
        registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
    }

    func testScheduleRoundsFailsWhenNothingCouldBeRegistered() async throws {
        let backend = RecordingAlarmBackend(failsEverySchedule: true)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 12))

        let outcome = await scheduler.scheduleRounds([chase(.noon, at: try date(6, 13))], on: try date(6, 12))

        XCTAssertEqual(outcome, .failed)
    }

    func testScheduleRoundsCountsOnlyTheAlarmsThatWereRegistered() async throws {
        let backend = RecordingAlarmBackend(failingAttempts: [0, 10])
        let scheduler = makeScheduler(backend: backend, now: try date(6, 12))

        let outcome = await scheduler.scheduleRounds([chase(.noon, at: try date(6, 13))], on: try date(6, 12))

        XCTAssertEqual(outcome, .scheduled(count: 38))
        let registered = await backend.registered
        XCTAssertEqual(registered.count, 38)
    }

    /// 旧い版（task_058）が登録した「追加の 1 回」の本が端末に残っていても、登録し直しと日ごとの取り消しで消える。
    func testRetiredExtraRoundAlarmsAreStillCancelled() async throws {
        let promiseDay = try date(6, 23, 45)
        let backend = RecordingAlarmBackend()
        let retired = AlarmPlan.retiredExtraIdentifiers(on: promiseDay, calendar: tokyo)
        XCTAssertEqual(retired.count, 40)
        await backend.seed(retired)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 9))

        // その日を登録し直すと、旧い追加の 1 回は消え、新しい回だけが残る。
        _ = await scheduler.scheduleRounds([chase(.evening, at: try date(6, 19))], on: promiseDay)
        let registered = await backend.registered
        XCTAssertTrue(registered.isDisjoint(with: Set(retired)))
        XCTAssertEqual(registered, Set(AlarmPlan.identifiers(on: promiseDay, round: .evening, calendar: tokyo)))

        // その日の全部の取り消しでも、旧い追加の 1 回が残らない。
        await backend.seed(retired)
        await scheduler.cancelDay(promiseDay)
        let afterCancel = await backend.registered
        XCTAssertTrue(afterCancel.isEmpty)
    }

    // MARK: 権限

    func testScheduleRoundsReturnsNotAuthorizedWhenDenied() async throws {
        let backend = RecordingAlarmBackend(state: .denied)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 12))

        let outcome = await scheduler.scheduleRounds([chase(.noon, at: try date(6, 13))], on: try date(6, 12))

        XCTAssertEqual(outcome, .notAuthorized)
        let events = await backend.events
        XCTAssertTrue(events.isEmpty)
    }

    /// 登録は起動や前面復帰のたびに呼ばれるので、ここでは権限を求めない
    /// （求めるのは約束する画面とオンボーディング）。
    func testScheduleRoundsDoesNotAskForAuthorization() async throws {
        let backend = RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .authorized)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 12))

        let outcome = await scheduler.scheduleRounds([chase(.noon, at: try date(6, 13))], on: try date(6, 12))

        XCTAssertEqual(outcome, .notAuthorized)
        let requests = await backend.authorizationRequests
        XCTAssertEqual(requests, 0)
        let scheduled = await backend.scheduled
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testRequestAuthorizationReportsWhetherItWasGranted() async throws {
        let granted = makeScheduler(
            backend: RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .authorized),
            now: try date(6, 15)
        )
        let refused = makeScheduler(
            backend: RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .denied),
            now: try date(6, 15)
        )

        let grantedResult = await granted.requestAuthorization()
        let refusedResult = await refused.requestAuthorization()
        XCTAssertTrue(grantedResult)
        XCTAssertFalse(refusedResult)
    }

    // MARK: 取り消し

    private func scheduleThreeRounds(_ scheduler: AlarmScheduler, on day: Date, dayOfMonth: Int) async throws {
        _ = await scheduler.scheduleRounds(
            [
                chase(.morning, at: try date(dayOfMonth, 8)),
                chase(.noon, at: try date(dayOfMonth, 13)),
                chase(.evening, at: try date(dayOfMonth, 21)),
            ],
            on: day
        )
    }

    func testCancelRoundCancelsOnlyThatRound() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        try await scheduleThreeRounds(scheduler, on: day, dayOfMonth: 6)
        await backend.clearEvents()

        // その日のどの時刻を渡しても同じ識別子になる。
        await scheduler.cancelRound(.noon, on: try date(6, 13, 10))

        let cancelled = await backend.cancelledIDs
        XCTAssertEqual(cancelled, AlarmPlan.identifiers(on: day, round: .noon, calendar: tokyo))
        let registered = await backend.registered
        XCTAssertEqual(
            registered,
            Set(
                AlarmPlan.identifiers(on: day, round: .morning, calendar: tokyo)
                    + AlarmPlan.identifiers(on: day, round: .evening, calendar: tokyo)
            )
        )
    }

    func testCancelDayCancelsEveryIdentifierOfThatDay() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        try await scheduleThreeRounds(scheduler, on: day, dayOfMonth: 6)
        await backend.clearEvents()

        await scheduler.cancelDay(try date(6, 21, 45))

        // 1 本も登録していない識別子（追加の 1 回）の取り消しはエラーになるが、最後まで進む。
        let cancelled = await backend.cancelledIDs
        XCTAssertEqual(cancelled, AlarmPlan.allIdentifiers(on: day, calendar: tokyo))
        let registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
    }

    func testCancelDayLeavesAnotherDayAlone() async throws {
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 7))
        try await scheduleThreeRounds(scheduler, on: try date(6, 7), dayOfMonth: 6)
        _ = await scheduler.scheduleRounds([chase(.morning, at: try date(7, 8))], on: try date(7, 7))

        await scheduler.cancelDay(try date(6, 16))

        let registered = await backend.registered
        XCTAssertEqual(registered, Set(AlarmPlan.identifiers(on: try date(7, 16), round: .morning, calendar: tokyo)))
    }

    /// 旧い識別子（回を持たない、日付 + 連番）で登録済みのアラームも、一覧からまとめて取り消す。
    func testCancelAllCancelsEverythingRegisteredIncludingLegacyIdentifiers() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        try await scheduleThreeRounds(scheduler, on: day, dayOfMonth: 6)
        let legacy = AlarmPlan.legacyIdentifiers(on: try date(4, 16), calendar: tokyo)
        await backend.seed(legacy)

        await scheduler.cancelAll()

        let registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
        let cancelled = await backend.cancelledIDs
        XCTAssertTrue(Set(cancelled).isSuperset(of: legacy))
    }

    /// 一覧が取れないときは、前日・当日・翌日の、いまの識別子と旧い識別子を取り消す。
    func testCancelAllFallsBackToKnownIdentifiersWhenTheListIsUnavailable() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)
        try await scheduleThreeRounds(scheduler, on: day, dayOfMonth: 6)
        await backend.seed(AlarmPlan.legacyIdentifiers(on: try date(5, 16), calendar: tokyo))
        await backend.failListing()

        await scheduler.cancelAll()

        let registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
    }

    // MARK: 音と題

    /// 結果を聞く回の題は、渡された「最初にやること」の文字。無ければ従来の題。約束を促す回は常に固定の題。
    func testChaseRoundsUseTheTitleTheyCarryAndFallBackToTheFixedOne() async throws {
        let day = try date(6, 7)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: day)

        _ = await scheduler.scheduleRounds(
            [
                AlarmRoundRequest(
                    round: .morning, start: try date(6, 8), voiceRelativePath: nil, purpose: .prompt, title: "資料を開く"
                ),
                chase(.noon, at: try date(6, 13), title: "資料を開く"),
                chase(.evening, at: try date(6, 21)),
            ],
            on: day
        )

        let scheduled = await backend.scheduled
        XCTAssertEqual(scheduled.count, 120)
        XCTAssertTrue(scheduled.prefix(40).allSatisfy { $0.title == PromiseCopy.alarmPromptTitle })
        XCTAssertTrue(scheduled.dropFirst(40).prefix(40).allSatisfy { $0.title == "資料を開く" })
        XCTAssertTrue(scheduled.suffix(40).allSatisfy { $0.title == PromiseCopy.alarmTitle })
    }

    func testChaseRoundsUseTheExportedVoiceAndThePromptRoundUsesTheDefaultSound() async throws {
        let (soundStore, audioFiles) = makeSoundStore()
        let day = try date(6, 7)
        let allocation = try audioFiles.allocate(recordedAt: day, calendar: tokyo)
        try AlarmTestAudio.writeVoice(to: allocation.url, seconds: 2)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, soundStore: soundStore, now: day)

        let outcome = await scheduler.scheduleRounds(
            [
                AlarmRoundRequest(round: .morning, start: try date(6, 8), voiceRelativePath: nil, purpose: .prompt),
                chase(.noon, at: try date(6, 13), voice: allocation.relativePath),
            ],
            on: day
        )

        XCTAssertEqual(outcome, .scheduled(count: 80))
        let expectedName = soundStore.fileName(for: day, calendar: tokyo)
        let scheduled = await backend.scheduled
        let prompt = scheduled.prefix(40)
        let noon = scheduled.suffix(40)
        XCTAssertTrue(prompt.allSatisfy { $0.soundName == nil && $0.title == PromiseCopy.alarmPromptTitle })
        XCTAssertTrue(noon.allSatisfy { $0.soundName == expectedName && $0.title == PromiseCopy.alarmTitle })
        let soundURL = soundStore.url(for: day, calendar: tokyo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)))

        // 1 回分を取り消しても、ほかの回が使う音は残す。その日の全部を取り消すと音のファイルも消える。
        await scheduler.cancelRound(.noon, on: day)
        XCTAssertTrue(FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)))
        await scheduler.cancelDay(day)
        XCTAssertFalse(FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)))
    }

    func testScheduleRoundsFallsBackToTheDefaultSound() async throws {
        let (soundStore, _) = makeSoundStore()
        let day = try date(6, 12)

        // 文字で約束した日（声が無い）。
        let voiceless = RecordingAlarmBackend()
        _ = await makeScheduler(backend: voiceless, soundStore: soundStore, now: day)
            .scheduleRounds([chase(.noon, at: try date(6, 13))], on: day)
        let voicelessNames = await voiceless.scheduled.map(\.soundName)
        XCTAssertEqual(voicelessNames.count, 40)
        XCTAssertTrue(voicelessNames.allSatisfy { $0 == nil })

        // 声のファイルが見つからず、書き出せなかった日。
        let missing = RecordingAlarmBackend()
        let outcome = await makeScheduler(backend: missing, soundStore: soundStore, now: day)
            .scheduleRounds([chase(.noon, at: try date(6, 13), voice: "2026/10/missing.m4a")], on: day)
        XCTAssertEqual(outcome, .scheduled(count: 40))
        let missingNames = await missing.scheduled.map(\.soundName)
        XCTAssertTrue(missingNames.allSatisfy { $0 == nil })
    }
}
